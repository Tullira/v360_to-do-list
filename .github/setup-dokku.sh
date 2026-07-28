#!/usr/bin/env bash
#
# Provisiona o app no Dokku. Rode como root na droplet, depois que o Dokku ja
# estiver instalado (isso e trabalho do user_data.sh).
#
#   APP_DOMAIN=todo.exemplo.com \
#   LETSENCRYPT_EMAIL=voce@exemplo.com \
#   PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)" \
#     bash setup-dokku.sh
#
# E idempotente de proposito: rodar de novo nao duplica app, dominio, linha do
# fstab nem arquivo de swap. Rode a segunda vez depois do primeiro deploy para
# que a etapa de SSL execute (o Let's Encrypt precisa de um vhost ja publicado).
set -euo pipefail

APP_NAME="${APP_NAME:-to-do-list}"
DB_SERVICE="${DB_SERVICE:-${APP_NAME}-db}"
APP_DOMAIN="${APP_DOMAIN:?defina APP_DOMAIN (ex.: todo.exemplo.com)}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:?defina LETSENCRYPT_EMAIL}"
PUBLIC_KEY="${PUBLIC_KEY:-}"
SWAP_SIZE_MB="${SWAP_SIZE_MB:-2048}"
SWAP_FILE=/var/swap.img

log() { printf '\n==> %s\n' "$*"; }

# --------------------------------------------------------------------------
# nginx: remove a pagina padrao para o vhost do app assumir a porta 80
# --------------------------------------------------------------------------
if [ -e /etc/nginx/sites-enabled/default ]; then
  log "Removendo a pagina padrao do nginx"
  rm -f /etc/nginx/sites-enabled/default
  systemctl reload nginx
fi

# --------------------------------------------------------------------------
# App
# --------------------------------------------------------------------------
if ! dokku apps:exists "$APP_NAME" >/dev/null 2>&1; then
  log "Criando o app $APP_NAME"
  dokku apps:create "$APP_NAME"
fi

# O workflow empurra HEAD:refs/heads/master; deixamos isso explicito para nao
# depender do default global do Dokku.
dokku git:set "$APP_NAME" deploy-branch master

# --------------------------------------------------------------------------
# Chave de deploy (a mesma cuja privada vai no secret DOKKU_SSH_PRIVATE_KEY)
# --------------------------------------------------------------------------
if [ -n "$PUBLIC_KEY" ]; then
  if ! dokku ssh-keys:list 2>/dev/null | grep -q "NAME=\"deploy\""; then
    log "Adicionando a chave publica de deploy"
    printf '%s\n' "$PUBLIC_KEY" | dokku ssh-keys:add deploy
  fi
fi

# --------------------------------------------------------------------------
# Variaveis de ambiente
#
# Este projeto autentica por sessao nativa do Rails - nao ha JWT. O segredo que
# importa e o SECRET_KEY_BASE, que assina o cookie de sessao: troca-lo desloga
# todo mundo, entao so geramos se ainda nao existir.
# --------------------------------------------------------------------------
if [ -z "$(dokku config:get "$APP_NAME" SECRET_KEY_BASE 2>/dev/null || true)" ]; then
  log "Gerando SECRET_KEY_BASE"
  dokku config:set --no-restart "$APP_NAME" "SECRET_KEY_BASE=$(openssl rand -hex 64)"
fi

# APP_HOST alimenta o config.hosts de producao. Sem ele a aplicacao nao sobe:
# lista vazia faria o Rails aceitar qualquer cabecalho Host.
dokku config:set --no-restart "$APP_NAME" \
  RAILS_ENV=production \
  RAILS_LOG_TO_STDOUT=true \
  RAILS_MAX_THREADS=3 \
  "APP_HOST=$APP_DOMAIN"

# --------------------------------------------------------------------------
# Banco
#
# O link com --alias DB faz o Dokku exportar DB_URL em vez de DATABASE_URL, e
# dali derivamos as variaveis discretas que config/database.yml le. Usar
# DATABASE_URL e proibido neste projeto: o Rails a mescla sobre a config do
# ambiente atual, o que faria a suite de teste apontar para outro banco.
# --------------------------------------------------------------------------
if ! dokku plugin:list | grep -q '^  postgres '; then
  log "Instalando o plugin postgres"
  dokku plugin:install https://github.com/dokku/dokku-postgres.git
fi

if ! dokku postgres:list 2>/dev/null | grep -qw "$DB_SERVICE"; then
  log "Criando o servico de banco $DB_SERVICE"
  dokku postgres:create "$DB_SERVICE"
fi

if ! dokku postgres:info "$DB_SERVICE" --links 2>/dev/null | grep -qw "$APP_NAME"; then
  log "Ligando $DB_SERVICE em $APP_NAME"
  dokku postgres:link "$DB_SERVICE" "$APP_NAME" --alias DB --no-restart
fi

log "Derivando DB_HOST/DB_PORT/DB_USERNAME/DB_PASSWORD/DB_NAME_PRODUCTION"
DB_URL="$(dokku config:get "$APP_NAME" DB_URL)"
# postgres://usuario:senha@host:porta/banco
url_body="${DB_URL#*://}"
credentials="${url_body%%@*}"
location="${url_body#*@}"
host_port="${location%%/*}"
port_and_db="${location#*:}"

dokku config:set --no-restart "$APP_NAME" \
  "DB_USERNAME=${credentials%%:*}" \
  "DB_PASSWORD=${credentials#*:}" \
  "DB_HOST=${host_port%%:*}" \
  "DB_PORT=${port_and_db%%/*}" \
  "DB_NAME_PRODUCTION=${location#*/}"

# --------------------------------------------------------------------------
# Portas e dominio
#
# O container de producao escuta na 80 (Thruster, EXPOSE 80 no Dockerfile),
# nao na 3000. O mapeamento https:443 quem adiciona e o letsencrypt:enable.
# --------------------------------------------------------------------------
log "Definindo o mapeamento de portas"
if ! dokku ports:set "$APP_NAME" http:80:80 2>/dev/null; then
  # Dokku < 0.31 ainda usa o namespace proxy:
  dokku proxy:ports-set "$APP_NAME" http:80:80
fi

log "Definindo o dominio $APP_DOMAIN"
dokku domains:clear "$APP_NAME" 2>/dev/null || true
dokku domains:add "$APP_NAME" "$APP_DOMAIN"

if command -v ufw >/dev/null 2>&1; then
  log "Liberando HTTP e HTTPS no firewall"
  ufw allow 80/tcp
  ufw allow 443/tcp
fi

# --------------------------------------------------------------------------
# Swap
# --------------------------------------------------------------------------
if ! swapon --show=NAME --noheadings 2>/dev/null | grep -qx "$SWAP_FILE"; then
  log "Criando ${SWAP_SIZE_MB}MB de swap em $SWAP_FILE"
  if [ ! -e "$SWAP_FILE" ]; then
    fallocate -l "${SWAP_SIZE_MB}M" "$SWAP_FILE" ||
      dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB"
  fi
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE"
  swapon "$SWAP_FILE"
fi

if ! grep -qF "$SWAP_FILE" /etc/fstab; then
  echo "$SWAP_FILE    none    swap    sw    0    0" >> /etc/fstab
fi

# --------------------------------------------------------------------------
# SSL
#
# O Let's Encrypt precisa de um vhost ja publicado: sem nenhum deploy nao ha
# app para validar. Na primeira execucao esta etapa e pulada - rode o script
# de novo depois do primeiro deploy.
# --------------------------------------------------------------------------
if dokku ps:report "$APP_NAME" --deployed 2>/dev/null | grep -qw true; then
  if ! dokku plugin:list | grep -q '^  letsencrypt '; then
    log "Instalando o plugin letsencrypt"
    dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git
  fi

  log "Emitindo certificado para $APP_DOMAIN"
  dokku letsencrypt:set "$APP_NAME" email "$LETSENCRYPT_EMAIL"
  dokku letsencrypt:enable "$APP_NAME"
  # Renovacao automatica: o cron cuida disso, nao precisa de auto-renew manual.
  dokku letsencrypt:cron-job --add
else
  # A aplicacao roda com config.assume_ssl = true, que faz o Rails tratar toda
  # requisicao como HTTPS independentemente da conexao real: o redirect do
  # force_ssl nao dispara e os cookies saem marcados Secure. Enquanto o
  # certificado nao existe, isso significa HSTS anunciado em conexao em claro e
  # cookie de sessao trafegando sem criptografia. A correcao aqui e
  # operacional, nao de codigo - por isso o aviso.
  log "SSL pulado: $APP_NAME ainda nao tem deploy."
  echo "    !!! ATE O CERTIFICADO SER EMITIDO A APP RESPONDE EM HTTP PURO."
  echo "    !!! NAO divulgue o dominio nem crie contas reais antes disso."
  echo "    Faca o primeiro deploy (push em master) e rode este script de novo."
fi

log "Pronto. App: $APP_NAME | dominio: $APP_DOMAIN | banco: $DB_SERVICE"
