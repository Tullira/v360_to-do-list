# Segurança

Auditoria da aplicação inteira: controllers, models, views, configuração de
ambiente, sessão/cookies, schema, Docker, workflows do GitHub Actions, scripts
de provisionamento e dependências do `Gemfile.lock`.

**Resultado:** as invariantes de autorização documentadas em
[`ARQUITETURA.md`](ARQUITETURA.md) estão implementadas e cobertas por spec. Não
há IDOR, mass assignment, SQL injection nem XSS. As 11 falhas encontradas estão
nas camadas que o projeto ainda não construiu: controles anti-abuso, cabeçalhos
de segurança, ciclo de vida da sessão e endurecimento do CI/CD.

Cada achado traz **onde está**, **por que é falha**, **como resolver** (com o
código) e **como provar que corrigiu** (o spec de regressão).

**Status: as 11 foram corrigidas** na branch `security/hardening`. As seções
abaixo continuam descrevendo a falha original e o raciocínio — é o registro de
*por que* cada defesa existe, e é o que impede alguém de removê-la por parecer
supérflua.

| # | Severidade | Falha | Status |
|---|---|---|---|
| [V-01](#v-01) | 🔴 Alta | Zero rate limiting em login e cadastro | ✅ corrigida |
| [V-02](#v-02) | 🟠 Média-Alta | Nenhuma Content-Security-Policy | ✅ corrigida |
| [V-03](#v-03) | 🟠 Média | Sessão sem expiração e sem revogação | ✅ corrigida |
| [V-04](#v-04) | 🟠 Média | `config.hosts` vazio em produção | ✅ corrigida |
| [V-05](#v-05) | 🟡 Baixa-Média | Guard de prefetch desliga a sessão em qualquer método | ✅ corrigida |
| [V-06](#v-06) | 🟡 Média-Baixa | Política de senha fraca | ✅ corrigida |
| [V-07](#v-07) | 🟡 Média-Baixa | Sem limites de tamanho/quantidade | ✅ corrigida |
| [V-08](#v-08) | 🟡 Média-Baixa | Workflows sem `permissions:`, actions por tag móvel | ✅ corrigida |
| [V-09](#v-09) | 🟡 Baixa | Host key SSH por TOFU no deploy | ✅ corrigida |
| [V-10](#v-10) | 🟡 Baixa | Janela HTTP no primeiro deploy vs. `assume_ssl` | ✅ corrigida |
| [V-11](#v-11) | 🔵 Baixa | Corrida na validação de unicidade devolve 500 | ✅ corrigida |

### Onde a implementação divergiu desta auditoria

Três receitas daqui não sobreviveram ao contato com a execução:

- **V-02, o nonce da CSP.** A sugestão era `request.session.id.to_s`. O id da
  sessão é `nil` enquanto nada foi gravado nela, então o nonce saía **vazio** —
  o `<script type="importmap">`, que é inline, seria bloqueado no primeiro
  acesso de qualquer visitante. Pior: o valor passava a existir ou não conforme
  a requisição anterior, o que fazia as duas respostas de login diferirem e
  reintroduzia o canal de enumeração que a V-02 não deveria tocar. Foi o
  `authorization_spec` que pegou. Agora o nonce é sorteado uma vez e guardado em
  `session[:csp_nonce]`.
- **V-06, limite de 72 bytes e `confirmation: true`.** Já vêm do
  `has_secure_password` no Rails 7.1+. Repetir renderia duas mensagens de erro
  para a mesma falha. O que faltava era só expor `password_confirmation` no
  formulário e nos Strong Parameters.
- **Permissions-Policy (item informativo).** `config.permissions_policy` emite
  o cabeçalho antigo `Feature-Policy` — o próprio actionpack 8.1 registra que
  Permissions-Policy "isn't yet supported by Rails". Feature-Policy foi
  descontinuado e navegador atual o ignora. O cabeçalho real vai por
  `config.action_dispatch.default_headers`.

**Continua pendente, porque é operacional e não de código:**

- preencher o secret `DOKKU_HOST_KEY` (V-09) — **sem ele o próximo deploy em
  master falha de propósito**;
- não divulgar o domínio antes da emissão do certificado (V-10);
- trocar o `memory_store` por um store compartilhado se a aplicação passar de um
  processo Puma (V-01), senão o limite efetivo vira N × 10.

---

<a id="v-01"></a>

## 🔴 V-01 — Zero rate limiting em login e cadastro

**Onde:** `app/controllers/sessions_controller.rb:14`,
`app/controllers/users_controller.rb:8`

**O problema.** Tentativas de login ilimitadas: sem lockout por conta, throttle
por IP, backoff ou CAPTCHA. Com senha mínima de 8 caracteres e sem verificação
contra senhas vazadas, credential stuffing é limitado apenas pelo custo do
bcrypt e pelas 3 threads do Puma (`RAILS_MAX_THREADS=3` em `setup-dokku.sh:72`).

Há um segundo efeito, menos óbvio: saturar as 3 threads com bcrypt derruba a
aplicação para todos os usuários — **o login é um amplificador de DoS**. E a
defesa contra enumeração por timing (`DUMMY_PASSWORD_DIGEST`), correta do ponto
de vista de privacidade, garante que até e-mails inexistentes custem um bcrypt
completo, barateando esse DoS.

`UsersController#create` tem o problema espelhado: criação ilimitada de contas
enchendo o Postgres da droplet sem custo para o atacante.

### Como resolver

`rate_limit` nativo do Rails 8 — sem gem nova.

```ruby
# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  # by: o IP, e nao o e-mail: limitar por e-mail deixaria o atacante travar a
  # conta de terceiros de proposito (DoS por lockout) e ainda revelaria quais
  # e-mails existem, desfazendo a defesa de enumeracao.
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
    flash.now[:alert] = "Muitas tentativas. Tente de novo em alguns minutos."
    render :new, status: :too_many_requests
  }
```

```ruby
# app/controllers/users_controller.rb
  rate_limit to: 5, within: 1.hour, only: :create, with: -> {
    flash.now[:alert] = "Muitos cadastros a partir deste endereco. Tente mais tarde."
    render :new, status: :too_many_requests
  }
```

**Pré-requisito.** `rate_limit` usa `Rails.cache`, e produção está sem
`cache_store` configurado (`config/environments/production.rb:47` comentado).
Numa droplet única com 1 processo Puma, `:memory_store` resolve:

```ruby
# config/environments/production.rb
config.cache_store = :memory_store, { size: 32.megabytes }
```

Escalar para múltiplos workers ou máquinas passa a exigir um store compartilhado
(Solid Cache ou Redis) — com `:memory_store` cada processo conta separado e o
limite efetivo vira N × 10.

**Spec de regressão** (`spec/requests/rate_limit_spec.rb`):

```ruby
it "bloqueia depois de 10 tentativas" do
  11.times { post login_path, params: { email: "ana@example.com", password: "errada" } }

  expect(response).to have_http_status(:too_many_requests)
end

it "aplica o mesmo limite para e-mail existente e inexistente" do
  # Senao o proprio rate limit vira o oraculo que o DUMMY_PASSWORD_DIGEST fecha.
  10.times { post login_path, params: { email: "ana@example.com", password: "errada" } }
  existente = response.status

  travel 4.minutes
  10.times { post login_path, params: { email: "ninguem@example.com", password: "errada" } }

  expect(response.status).to eq(existente)
end
```

---

<a id="v-02"></a>

## 🟠 V-02 — Nenhuma Content-Security-Policy

**Onde:** `config/initializers/content_security_policy.rb` **não existe**;
`app/views/layouts/application.html.erb:8`

**O problema.** O layout chama `<%= csp_meta_tag %>`, mas sem política
configurada o helper não emite nada e **nenhum cabeçalho
`Content-Security-Policy` é enviado**. Hoje o escapamento automático do ERB
segura o XSS — não há um único `html_safe`, `raw` ou `<%==` em `app/` —, mas é
uma linha de defesa só. Qualquer `html_safe` futuro ou falha em dependência de
renderização vira execução de JavaScript arbitrário sem nada para contê-la.

Sem CSP, um XSS não fica limitado pelo `httponly`: o atacante não rouba o
cookie, mas age como o usuário e exfiltra dados via `fetch()` para domínio
externo.

### Como resolver — em duas partes, nesta ordem

**Parte 1: remover os handlers inline.** Existem dois
`onchange="this.form.requestSubmit()"` — `app/views/lists/show.html.erb:77` e
`app/views/tasks/show.html.erb:58`. Uma CSP estrita quebra os dois, e a saída
preguiçosa (`'unsafe-inline'`) esvaziaria a proteção inteira. Virem Stimulus:

```javascript
// app/javascript/controllers/autosubmit_controller.js
import { Controller } from "@hotwired/stimulus"

// Envia o formulario assim que o campo muda. Existe para tirar o
// onchange="..." inline das views: handler inline exige 'unsafe-inline' na
// CSP, o que anularia a protecao contra XSS.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
```

```erb
<%# app/views/lists/show.html.erb e app/views/tasks/show.html.erb %>
<%= form_with model: [ @list, task ], url: list_task_path(@list, task), method: :patch,
              class: "pt-0.5",
              data: { controller: "autosubmit", action: "change->autosubmit#submit" } do |f| %>
  <%= f.check_box :completed, id: "task_#{task.id}_completed", class: "checkbox" %>
```

Registrar o controller em `app/javascript/controllers/index.js`. Os specs de
sistema existentes (`spec/system/tasks_spec.rb`) cobrem esse comportamento e
devem continuar verdes **sem alteração** — é exatamente a prova de que o
refactor foi neutro.

**Parte 2: a política.**

```ruby
# config/initializers/content_security_policy.rb
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self
    policy.img_src     :self, :data
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self
    policy.base_uri    :self
    policy.form_action :self
    # frame_ancestors :none substitui o X-Frame-Options em navegador moderno.
    policy.frame_ancestors :none
  end

  # Nonce para os poucos <script> que o Rails/Turbo injeta inline.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Suba em report_only primeiro em desenvolvimento: o console do navegador
  # lista o que quebraria antes de a politica passar a bloquear de verdade.
  config.content_security_policy_report_only = Rails.env.development?
end
```

**Spec de regressão:**

```ruby
it "envia Content-Security-Policy sem 'unsafe-inline'" do
  sign_in_via_request(owner)
  get lists_path

  csp = response.headers["Content-Security-Policy"]
  expect(csp).to include("script-src 'self'")
  expect(csp).not_to include("unsafe-inline")
end
```

---

<a id="v-03"></a>

## 🟠 V-03 — Sessão sem expiração e sem revogação

**Onde:** `config/initializers/session_store.rb` não existe;
`app/controllers/concerns/session_management.rb`

**O problema.** O cookie store padrão guarda o estado **inteiramente no cookie
do cliente** — o servidor não retém nada. Daí:

1. **`reset_session` no logout não invalida nada de verdade.** Ele apenas manda
   o navegador substituir o cookie. Um cookie copiado antes (malware, máquina
   compartilhada, backup de perfil, log de proxy) continua autenticando
   indefinidamente. O item 2 da tabela de decisões em `ARQUITETURA.md` afirma
   "logout é imediato" — verdade para o navegador da vítima, falso para uma
   cópia do cookie.
2. **Não há `expire_after`.** É um cookie de sessão de navegador, e navegadores
   modernos restauram sessões — na prática, login sem prazo de validade.

### Como resolver

Decisão registrada: manter o cookie store (não vale a migration de
`session_token` para o risco atual) e resolver com expiração em duas camadas —
uma no cliente, outra que o cliente não controla.

```ruby
# config/initializers/session_store.rb
# expire_after e uma instrucao ao navegador: util, mas o cliente pode ignora-la.
# A validade real e conferida no servidor (ver SessionManagement#session_expired?).
Rails.application.config.session_store :cookie_store,
  key: "_to_do_list_session",
  expire_after: 2.weeks,
  same_site: :lax,
  httponly: true,
  secure: Rails.env.production?
```

```ruby
# app/controllers/concerns/session_management.rb
SESSION_MAX_AGE = 2.weeks

def start_session_for(user)
  reset_session
  session[:user_id] = user.id
  # Carimbo assinado dentro do proprio cookie: o cliente nao consegue adiar a
  # expiracao remexendo no atributo Expires do cookie.
  session[:created_at] = Time.current.to_i
end

def session_expired?
  created_at = session[:created_at]
  created_at.blank? || Time.at(created_at) < SESSION_MAX_AGE.ago
end
```

```ruby
# app/controllers/application_controller.rb
def require_login
  if signed_in? && session_expired?
    reset_session
    return redirect_to login_path, alert: "Sua sessao expirou. Faca login de novo."
  end

  return if signed_in?

  redirect_to login_path, alert: "Faca login para continuar"
end
```

**Spec de regressão:**

```ruby
it "expira a sessao depois de duas semanas" do
  sign_in_via_request(owner)

  travel 2.weeks + 1.day
  get lists_path

  expect(response).to redirect_to(login_path)
end
```

**Corrigir também a documentação:** a tabela de decisões do `ARQUITETURA.md`
precisa dizer que o logout é imediato *no navegador do usuário*, e que revogar
um cookie já copiado exigiria estado no servidor — limitação aceita
conscientemente.

---

<a id="v-04"></a>

## 🟠 V-04 — `config.hosts` vazio em produção

**Onde:** `config/environments/production.rb:79-85` (bloco comentado)

**O problema.** O Rails só popula `config.hosts` em development. Em produção a
lista fica vazia e o `ActionDispatch::HostAuthorization` **aceita qualquer
cabeçalho `Host`**, o que permite envenenar URLs absolutas geradas pela
aplicação, ataques de DNS rebinding contra a droplet e respostas servidas para
domínios de terceiros apontados para o IP. O alcance hoje é pequeno — quase tudo
usa path relativo — mas cresce no instante em que aparecer recuperação de senha
ou qualquer e-mail transacional.

### Como resolver

```ruby
# config/environments/production.rb
config.hosts = [ ENV.fetch("APP_HOST") ]
# O healthcheck do Dokku bate no container pelo IP interno, sem o Host do
# dominio - sem esta excecao o /up passa a responder 403 e o deploy trava.
config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
```

```bash
# .github/setup-dokku.sh, junto do dokku config:set existente
dokku config:set --no-restart "$APP_NAME" \
  RAILS_ENV=production \
  RAILS_LOG_TO_STDOUT=true \
  RAILS_MAX_THREADS=3 \
  "APP_HOST=$APP_DOMAIN"
```

**Spec de regressão:**

```ruby
it "recusa Host forjado" do
  # Precisa rodar com a config de producao carregada, ou stubar config.hosts.
  get lists_path, headers: { "Host" => "atacante.example.com" }

  expect(response).to have_http_status(:forbidden)
end
```

---

<a id="v-05"></a>

## 🟡 V-05 — O guard de prefetch desliga a gravação de sessão em qualquer método HTTP

**Onde:** `app/controllers/application_controller.rb:19-24`

```ruby
def isolate_prefetch_from_session
  return unless request.headers["X-Sec-Purpose"] == "prefetch"
  flash.keep
  request.session_options[:skip] = true
end
```

**O problema.** O guard confia num cabeçalho controlado pelo cliente e **não
filtra por método HTTP**. Uma requisição `POST /login` ou `DELETE /logout` com
`X-Sec-Purpose: prefetch` faz o Rack pular o `Set-Cookie`: no login o
`session[:user_id]` nunca é persistido; **no logout o `reset_session` roda no
servidor mas o navegador mantém o cookie antigo, que continua válido — o logout
silenciosamente não acontece.**

Exploração cross-site está bloqueada hoje: cabeçalho customizado exige preflight
CORS e `config/initializers/cors.rb` está inteiramente comentado, então o
navegador nem chega a enviar a requisição. Por isso é Baixa-Média e não Alta.
Mas a proteção vem de um efeito colateral da ausência de CORS, não de uma
decisão — se o CORS for ligado um dia, isto vira falha real.

### Como resolver

Uma linha. Prefetch só existe para navegação; nenhum método que escreve sessão
deveria entrar nesse caminho:

```ruby
def isolate_prefetch_from_session
  # Prefetch e sempre GET. Aceitar o cabecalho em POST/DELETE deixaria uma
  # requisicao do cliente desligar a gravacao da sessao - e um logout que nao
  # manda Set-Cookie nao desloga ninguem.
  return unless request.get? || request.head?
  return unless request.headers["X-Sec-Purpose"] == "prefetch"

  flash.keep
  request.session_options[:skip] = true
end
```

**Spec de regressão** (em `spec/requests/flash_spec.rb`):

```ruby
it "desloga de verdade mesmo com o cabecalho de prefetch forjado" do
  sign_in_via_request(owner)

  delete logout_path, headers: { "X-Sec-Purpose" => "prefetch" }
  get lists_path

  expect(response).to redirect_to(login_path)
end
```

---

<a id="v-06"></a>

## 🟡 V-06 — Política de senha fraca

**Onde:** `app/models/user.rb:17`, `app/views/users/new.html.erb:19-23`

**O problema.** `validates :password, length: { minimum: 8 }` é o único
requisito. Não há:

- verificação contra senhas comuns/vazadas — `senha123` e `12345678` passam;
- **limite superior**: o bcrypt trunca em 72 bytes silenciosamente, então uma
  "senha" de 200 caracteres não é mais forte que os primeiros 72 — e o usuário
  acredita que é;
- `password_confirmation` no cadastro. Como **não existe recuperação de senha em
  nenhum lugar do projeto**, um erro de digitação tranca a conta para sempre.

Combinado com V-01, o mínimo de 8 caracteres sem lista de bloqueio é o que torna
a força bruta viável na prática.

### Como resolver

```ruby
# app/models/user.rb
# As mais usadas em vazamentos publicos, ja normalizadas. Nao substitui uma
# checagem contra base de vazamentos, mas corta o alvo mais facil.
COMMON_PASSWORDS = %w[
  12345678 123456789 1234567890 password senha123 qwertyui abc12345
  iloveyou princess sunshine password1 football baseball welcome1
].freeze

validates :password,
          length: { minimum: 8, maximum: 72 },  # 72: limite do bcrypt, que trunca em silencio
          confirmation: true,
          allow_nil: true
validate :password_not_common

private

def password_not_common
  return if password.blank?
  return unless COMMON_PASSWORDS.include?(password.downcase)

  errors.add(:password, "e facil demais de adivinhar. Escolha outra.")
end
```

```ruby
# app/controllers/users_controller.rb
def user_params
  params.require(:user).permit(:username, :email, :password, :password_confirmation)
end
```

```erb
<%# app/views/users/new.html.erb, depois do campo de senha %>
<div>
  <%= f.label :password_confirmation, "Confirme a senha", class: "field-label" %>
  <%= f.password_field :password_confirmation, autocomplete: "new-password", class: "field" %>
</div>
```

**Specs** em `spec/models/user_spec.rb`: senha comum rejeitada, senha acima de
72 bytes rejeitada, confirmação divergente rejeitada.

---

<a id="v-07"></a>

## 🟡 V-07 — Sem limites de tamanho ou de quantidade: exaustão de recursos

**Onde:** `app/models/list.rb:6`, `app/models/task.rb:4`,
`app/controllers/lists_controller.rb:7`, `app/views/lists/index.html.erb:43`

**O problema.**

- `List#name` e `Task#title` só validam presença; `Task#description` é `text`
  sem limite algum. Um POST com vários MB de texto é aceito e persistido.
- Não há cota por usuário: nada limita quantas listas/tarefas uma conta cria.
- `ListsController#index` faz `current_user.lists.includes(:tasks)` **sem
  paginação** e conta em Ruby (`list.tasks.count(&:completed?)`) — carrega
  *todas* as tarefas de *todas* as listas na memória a cada acesso à home.

Com V-01 (cadastro ilimitado), isto é um caminho barato para encher o disco da
droplet e estourar a memória dos 3 workers.

### Como resolver

```ruby
# app/models/list.rb
validates :name, presence: true, length: { maximum: 120 }

# app/models/task.rb
validates :title, presence: true, length: { maximum: 200 }
validates :description, length: { maximum: 10_000 }
```

Trocar a contagem em Ruby por agregação no banco — resolve o N+1 *e* para de
carregar todas as tarefas em memória:

```ruby
# app/controllers/lists_controller.rb
@lists = current_user.lists
                     .select("lists.*",
                             "COUNT(tasks.id) AS tasks_count",
                             "COUNT(tasks.id) FILTER (WHERE tasks.completed) AS completed_count")
                     .left_joins(:tasks)
                     .group("lists.id")
                     .order(created_at: :desc)
```

```erb
<%# app/views/lists/index.html.erb — no lugar de list.tasks.size / count(&:completed?) %>
<% total = list.tasks_count %>
<% concluidas = list.completed_count %>
```

Quando a listagem crescer, paginar. O `includes(:tasks)` pode sair junto — sem o
`count(&:block)` na view, ele deixa de ser necessário.

---

<a id="v-08"></a>

## 🟡 V-08 — Workflows sem `permissions:` e actions por tag móvel

**Onde:** `.github/workflows/ci.yml`, `.github/workflows/cd_main.yml`

**O problema.**

1. **Nenhum dos dois workflows declara `permissions:`.** O `GITHUB_TOKEN` recebe
   o padrão do repositório, que em repositórios mais antigos é *read/write em
   tudo*. Nenhum job precisa disso — o deploy usa chave SSH, não o token. Um
   comprometimento de qualquer step (gem maliciosa, action comprometida) ganha
   escrita no repositório.
2. **Actions referenciadas por tag móvel** (`actions/checkout@v6`,
   `ruby/setup-ruby@v1`, `actions/cache@v4`, `actions/upload-artifact@v4`).
   Tags são mutáveis: quem comprometer o repositório da action reescreve a tag e
   passa a executar código nos runners.

Vale registrar o acerto: a CI dispara em `pull_request`, **não**
`pull_request_target` — código de fork não alcança secrets.

### Como resolver

```yaml
# no topo de .github/workflows/ci.yml e .github/workflows/cd_main.yml,
# logo depois de `name:`
permissions:
  contents: read
```

E fixar cada action pelo SHA do commit, mantendo a tag no comentário:

```yaml
- uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8  # v6.0.0
```

O `dependabot.yml` já monitora `github-actions` semanalmente, então os SHAs
continuam sendo atualizados automaticamente — a pinagem não cria trabalho
manual.

---

<a id="v-09"></a>

## 🟡 V-09 — Host key SSH por TOFU no deploy

**Onde:** `.github/workflows/cd_main.yml:53-62`

**O problema.** Sem o secret `DOKKU_HOST_KEY` preenchido, o workflow cai em
`ssh-keyscan "$DOKKU_HOST"` e confia na chave apresentada naquele momento —
trust-on-first-use **em toda execução**, não só na primeira. Um atacante
posicionado na rede do runner pode se passar pelo servidor Dokku e receber o
push (que inclui todo o código-fonte); o `known_hosts` gerado no próprio job
valida a chave falsa alegremente.

O comentário no arquivo reconhece o problema e o commit `aed4091` melhorou o
diagnóstico, mas o secret continua **opcional**: o caminho inseguro é o padrão
para quem não leu o comentário.

### Como resolver

Tornar o secret obrigatório e remover o fallback:

```bash
- name: Preparar chave SSH
  env:
    SSH_PRIVATE_KEY: ${{ secrets.DOKKU_SSH_PRIVATE_KEY }}
    DOKKU_HOST: ${{ secrets.DOKKU_HOST }}
    DOKKU_HOST_KEY: ${{ secrets.DOKKU_HOST_KEY }}
  run: |
    install -m 700 -d ~/.ssh
    printf '%s\n' "$SSH_PRIVATE_KEY" > ~/.ssh/id_deploy
    chmod 600 ~/.ssh/id_deploy

    # Sem fallback para ssh-keyscan: confiar na chave apresentada agora e
    # trust-on-first-use a CADA execucao, e o push leva o codigo-fonte inteiro.
    if [ -z "$DOKKU_HOST_KEY" ]; then
      echo "::error::Preencha o secret DOKKU_HOST_KEY com a saida de 'ssh-keyscan $DOKKU_HOST' rodada de uma maquina confiavel."
      exit 1
    fi
    printf '%s\n' "$DOKKU_HOST_KEY" > ~/.ssh/known_hosts
    chmod 600 ~/.ssh/known_hosts

    if ! ssh-keygen -F "$DOKKU_HOST" -f ~/.ssh/known_hosts >/dev/null; then
      echo "::error::known_hosts nao tem entrada para '$DOKKU_HOST'. O secret precisa da linha completa, comecando pelo host."
      exit 1
    fi
```

É uma configuração única: rodar `ssh-keyscan <host>` da máquina do operador e
colar a saída no secret.

---

<a id="v-10"></a>

## 🟡 V-10 — Janela HTTP no primeiro deploy vs. `assume_ssl`

**Onde:** `config/environments/production.rb:25-28`,
`.github/setup-dokku.sh:160-174`

**O problema.** `config.assume_ssl = true` faz o Rails tratar toda requisição
como HTTPS **independentemente da conexão real** — o redirect do `force_ssl`
nunca dispara e os cookies saem marcados `Secure`. Já o `setup-dokku.sh` **pula
a etapa de Let's Encrypt na primeira execução** (linha 160: o vhost precisa
existir antes), instruindo a rodar o script de novo depois do primeiro deploy.

Entre o primeiro deploy e a segunda execução, a aplicação é servida por HTTP
puro se comportando como se fosse HTTPS: HSTS anunciado numa conexão em claro e
cookie de sessão trafegando sem criptografia se algum cliente o aceitar.

### Como resolver

A correção aqui é operacional, não de código: **não divulgar o domínio nem criar
contas reais antes da segunda execução do script.** Deixar isso explícito na
saída, para quem estiver provisionando não descobrir depois:

```bash
# .github/setup-dokku.sh, no lugar do else da linha 171
else
  log "SSL pulado: $APP_NAME ainda nao tem deploy."
  echo "    !!! ATE O CERTIFICADO SER EMITIDO A APP RESPONDE EM HTTP PURO."
  echo "    !!! NAO divulgue o dominio nem crie contas reais antes disso."
  echo "    Faca o primeiro deploy (push em master) e rode este script de novo."
fi
```

---

<a id="v-11"></a>

## 🔵 V-11 — Corrida na validação de unicidade devolve 500

**Onde:** `app/models/user.rb:10-14`, `db/schema.rb:43-44`

**O problema.** `validates :uniqueness` faz um `SELECT` antes do `INSERT`. Dois
cadastros simultâneos com o mesmo e-mail passam ambos pela validação e o segundo
bate no índice único do banco, levantando `ActiveRecord::RecordNotUnique` — não
tratado por nenhum `rescue_from`, virando erro 500. Não é falha de autorização,
mas é um 500 disparável por qualquer visitante (e, sem V-01, em volume).

### Como resolver

```ruby
# app/controllers/users_controller.rb
def create
  @user = User.new(user_params)

  if @user.save
    start_session_for(@user)
    redirect_to lists_path
  else
    render :new, status: :unprocessable_content
  end
# O indice unico do banco e a fonte de verdade; a validacao e so uma cortesia
# de UX e perde a corrida entre dois cadastros simultaneos.
rescue ActiveRecord::RecordNotUnique
  @user.errors.add(:email, "ja esta em uso")
  render :new, status: :unprocessable_content
end
```

---

## 🔵 Itens informativos

| Item | Onde | Como resolver |
|---|---|---|
| ✅ Sem `Permissions-Policy` | `config/initializers/permissions_policy.rb` | Corrigido, mas **não** com `config.permissions_policy`: esse helper emite o `Feature-Policy` antigo, que navegador atual ignora. O cabeçalho real vai por `config.action_dispatch.default_headers` |
| `db:prepare` automático a cada boot | `bin/docker-entrypoint:4-6` | Migration roda sozinha no deploy, sem revisão nem janela. Risco operacional, não de segurança: considerar um passo explícito de migration no workflow |
| Sem verificação de e-mail nem recuperação de senha | — | Funcionalidade ausente; enquanto isso, o e-mail não pode ser tratado como identidade confiável |
| ✅ `max_connections` em vez de `pool` | `config/database.yml` | Corrigido: renomeado para `pool`. O ActiveRecord ignorava a chave antiga e caía no padrão 5 |
| `filter_parameters` inclui `:email` | `config/initializers/filter_parameter_logging.rb:7` | Nada a fazer: está acima do padrão do Rails, registrado como acerto |

---

## O que está correto e não deve regredir

É a maior parte da superfície de ataque desta aplicação, e está sólida:

- **Autorização escopada na sessão.** Toda leitura/escrita passa por
  `current_user.lists` (`lists_controller.rb:48`, `tasks_controller.rb:47`).
  Nenhum caminho de IDOR.
- **404 em vez de 403 para recurso alheio**, com resposta byte a byte idêntica à
  de recurso inexistente — provado em `spec/requests/authorization_spec.rb:91`.
- **Strong Parameters sem `user_id`, `list_id` e `role`** — mass assignment
  fechado, com spec provando que os três são ignorados quando forjados.
- **Session fixation tratada** (`reset_session` antes de gravar o `user_id`).
- **Enumeração de e-mail fechada nos dois canais**: mensagem idêntica *e* custo
  de bcrypt idêntico, com spec para o segundo.
- **CSRF ligada** (`api_only = false`) com spec de regressão.
- **Zero XSS**: nenhum `html_safe`, `raw`, `<%==` ou `render inline` em `app/`.
- **Zero SQL injection**: nenhuma interpolação em query.
- **Cabeçalhos padrão do Rails ativos** (X-Frame-Options SAMEORIGIN,
  X-Content-Type-Options nosniff, Referrer-Policy) + HSTS via `force_ssl`.
- **Segredos fora do repositório**: `.gitignore` e `.dockerignore` cobrem
  `.env*`, `master.key` e chaves; `SECRET_KEY_BASE` gerado com
  `openssl rand -hex 64` e só regerado se ausente.
- **Imagem de produção roda como não-root** (`Dockerfile:64-66`).
- **Dependências atuais e sem CVE conhecida** (Rails 8.1.3, rack 3.2.6,
  nokogiri 1.19.4, puma 8.0.2), com `brakeman` + `bundler-audit` na CI e
  Dependabot semanal.
- **Droplet endurecida**: SSH só por chave, `ufw` liberando apenas 22/80/443.

---

## Verificação

Depois de aplicar qualquer correção:

```bash
docker compose run --rm app bundle exec rspec > /rails/suite.log 2>&1   # ler o arquivo pelo host
docker compose run --rm app bundle exec rubocop
docker compose run --rm app bin/brakeman --no-pager
docker compose run --rm app bin/bundler-audit
docker compose run --rm app bin/rails tailwindcss:build   # se alguma view mudou
```

Nenhum spec existente de autorização (`spec/requests/authorization_spec.rb`,
`spec/requests/flash_spec.rb`) pode precisar de edição. Se algum precisar para
voltar a passar, a correção quebrou uma invariante e deve ser revista.
