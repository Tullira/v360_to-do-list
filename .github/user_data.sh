#!/usr/bin/env bash
#
# user_data da droplet (DigitalOcean, EC2, ...): prepara uma Ubuntu limpa e
# instala o Dokku. Roda uma unica vez, como root, no primeiro boot. A saida vai
# para /var/log/cloud-init-output.log.
#
# Antes de subir a maquina, substitua ADMIN_PUBLIC_KEY pela sua chave publica -
# o acesso e exclusivamente por chave. Sem ela voce fica de fora da droplet
# (o console web do provedor continua sendo a saida de emergencia).
#
# Depois que a maquina subir, rode setup-dokku.sh para provisionar o app.
set -euo pipefail

DOKKU_TAG="${DOKKU_TAG:-v0.35.20}"
ADMIN_PUBLIC_KEY="${ADMIN_PUBLIC_KEY:-COLE_AQUI_SUA_CHAVE_PUBLICA}"

export DEBIAN_FRONTEND=noninteractive

echo "==> Atualizando pacotes"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq ca-certificates curl ufw

echo "==> Firewall: apenas SSH, HTTP e HTTPS"
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# SSH endurecido num drop-in com prefixo 00-: o sshd usa o primeiro valor que
# encontra, e o Include de sshd_config.d vem antes do corpo do arquivo. O 00-
# garante precedencia sobre o 50-cloud-init.conf que o provedor deixa la.
echo "==> Endurecendo o SSH (somente chave)"
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/00-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PermitEmptyPasswords no
EOF
chmod 600 /etc/ssh/sshd_config.d/00-hardening.conf

sshd -t
systemctl restart ssh 2>/dev/null || systemctl restart sshd

echo "==> Instalando o Dokku $DOKKU_TAG"
curl -fsSL https://dokku.com/bootstrap.sh -o /tmp/bootstrap.sh
DOKKU_TAG="$DOKKU_TAG" bash /tmp/bootstrap.sh
rm -f /tmp/bootstrap.sh

if [ "$ADMIN_PUBLIC_KEY" != "COLE_AQUI_SUA_CHAVE_PUBLICA" ]; then
  echo "==> Registrando a chave de administracao no Dokku"
  printf '%s\n' "$ADMIN_PUBLIC_KEY" | dokku ssh-keys:add admin
else
  echo "!!! ADMIN_PUBLIC_KEY nao foi preenchida: nenhuma chave registrada no Dokku."
fi

echo "==> Droplet pronta. Proximo passo: setup-dokku.sh"
