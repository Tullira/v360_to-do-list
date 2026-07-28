# CLAUDE.md

## Visão geral
To-do list em Ruby on Rails: **monólito full-stack** com Postgres, views ERB e
Hotwire (Turbo + Stimulus), estilizado com Tailwind. Autenticação por **sessão
nativa do Rails** — não há JWT nem API JSON. Todo o ambiente roda em Docker.
Desenvolvimento é guiado por TDD: nada de código em `app/` sem um teste
falhando antes.

O projeto chegou a ser API-only com JWT, mas o requisito de `Authorization:
Bearer` não era real e o cliente especificou apenas "Ruby on Rails". Só volte a
considerar API-only se aparecer um consumidor que não compartilha cookie com o
servidor (app mobile nativo, parceiro externo, múltiplos front-ends).

## Stack
- Ruby 3.4.9, Rails 8.1, PostgreSQL 17
- Hotwire (Turbo + Stimulus) via importmap, Tailwind CSS 4, Propshaft
- `bcrypt` (has_secure_password)
- RSpec, FactoryBot, Faker, Shoulda Matchers, SimpleCov
- Capybara + Cuprite (Chromium headless dentro do container)
- Docker + Docker Compose (`compose.yaml`, `Dockerfile.dev`)

## Comandos essenciais
Tudo roda dentro do container. `docker compose run --rm app` cria um container
efêmero; `exec` reaproveita o que já está de pé.

- `docker compose up -d` — sobe banco e aplicação (http://localhost:3000)
- `docker compose run --rm app bundle exec rspec` — suíte inteira
- `docker compose run --rm app bundle exec rspec spec/models` — só os rápidos
- `docker compose run --rm app bundle exec rubocop` — lint
- `docker compose run --rm app bin/rails db:migrate` — aplica migrations
- `docker compose run --rm app bin/rails tailwindcss:build` — recompila o CSS
- `docker compose logs -f app` — logs da aplicação
- `docker compose down` — derruba tudo (o volume `pgdata` sobrevive)

Depois de mexer no `Gemfile`: `docker compose build app`.

**A saída do `rspec` fica bufferizada** quando o comando roda pelo PowerShell —
para acompanhar ao vivo, redirecione para um arquivo no bind mount
(`... > /rails/suite.log 2>&1`) e leia o arquivo pelo host.

## Configuração e segredos
- `.env` (NÃO versionado) guarda `POSTGRES_PASSWORD` e `SECRET_KEY_BASE`.
  `.env.example` é o modelo versionado — mantenha os dois em sincronia.
- `SECRET_KEY_BASE` assina o cookie de sessão. Trocá-lo desloga todo mundo.
- `config/database.yml` lê variáveis discretas (`DB_HOST`, `DB_USERNAME`, …).
  **Não use `DATABASE_URL`**: o Rails a mescla sobre a config do ambiente atual,
  o que faria a suíte de teste apontar para o banco de desenvolvimento e
  apagá-lo.

## Fluxo obrigatório: TDD (Red → Green → Refactor)
1. Nunca escreva código de produção em `app/` sem um teste falhando antes.
2. Rode a suíte e mostre a falha real antes de implementar qualquer coisa.
3. Implemente apenas o mínimo necessário para o teste passar — sem features
   extras não pedidas.
4. Rode a suíte inteira antes de considerar uma tarefa concluída.
5. Não pule etapas mesmo quando a solução parecer óbvia.

## Onde cada tipo de teste mora
- `spec/models/` — validações, associações, regras de negócio.
- `spec/system/` — um teste por fluxo de usuário, no Chrome headless.
- `spec/requests/authorization_spec.rb` — cenários de segurança que um
  navegador **não consegue** produzir: forjar `user_id`/`list_id`/`role` no
  corpo da requisição, e a indistinguibilidade entre recurso alheio e
  inexistente. Não tente converter isto em spec de sistema: um formulário não
  tem os campos forjados, então o teste passaria sem provar nada.
- `spec/requests/flash_spec.rb` — o prefetch do Turbo não pode consumir nem
  sobrescrever a sessão. No navegador isso é uma corrida entre duas
  requisições; em request spec a sequência é determinística.

**Em spec de sistema, nunca use `expect { click_button ... }.to change(Model,
:count)`.** O Turbo envia o formulário por `fetch`, então não existe navegação
para o Capybara esperar: o clique retorna na hora e o matcher `change` — que
não tem retry — lê o contador antes de o POST terminar. O teste passa ou falha
conforme a carga da máquina. Sincronize primeiro numa asserção de tela
(`expect(page).to have_content(...)`, que espera até `Capybara.default_max_wait_time`)
e só depois consulte o banco:

```ruby
click_button "Criar lista"

expect(page).to have_content("Mercado")   # esta é a que espera
expect(owner.lists.count).to eq(1)
```

A mesma regra vale para `task.reload` logo após um `click_button`.

## Regras de segurança (não negociáveis)
- Nunca rodar migrations destrutivas (`db:drop`, `db:reset`, rollback em
  produção) sem antes pedir confirmação explícita em texto.
- Nunca commitar `config/master.key`, `.env` ou qualquer credencial.
- Nunca dar push direto em `main`/`master`. Sempre trabalhar em branch.
- Nunca rodar `git push --force` sem confirmação explícita.
- Nunca instalar uma gem nova sem perguntar antes.
- Nunca editar `schema.rb` manualmente — sempre via migration.
- Tratar todo dado vindo do usuário como não confiável: Strong Parameters e
  queries parametrizadas, nunca interpolar direto em SQL.

Boa parte dessas regras também está bloqueada tecnicamente em
`.claude/settings.json` (permission rules).

Vulnerabilidades conhecidas ainda em aberto (rate limiting, CSP, expiração de
sessão, `config.hosts`, endurecimento do CI/CD), cada uma com a correção
proposta e o spec de regressão: `docs/SEGURANCA.md`. Consulte antes de mexer em
autenticação, sessão ou workflows — o que for corrigido de lá sai da lista.

## Invariantes de autorização
Cada uma tem spec dedicado. Quebrar qualquer uma é regressão de segurança, não
mudança de comportamento:

- **A posse vem sempre da sessão.** Toda leitura/escrita é escopada em
  `current_user.lists`. `Task` não tem `user_id`: a posse é derivada de
  `list.user_id`.
- **Nunca confie em id vindo do payload.** `user_id` fica fora dos params
  permitidos de `List`; `list_id` fica fora dos de `Task`. A lista vem sempre da
  rota, já validada como do `current_user`.
- **Recurso alheio responde 404, nunca 403.** Um 403 confirmaria que aquele id
  existe e permitiria enumerar os recursos dos outros usuários. A resposta de
  recurso alheio e a de recurso inexistente são idênticas byte a byte.
- **Login não revela quais e-mails existem.** Senha errada e e-mail inexistente
  devolvem a mesma mensagem *e* gastam o mesmo tempo de bcrypt (ver
  `SessionsController::DUMMY_PASSWORD_DIGEST`) — mensagem igual sem custo igual
  ainda vaza por timing.
- **`reset_session` antes de gravar o `user_id`.** Ver o concern
  `SessionManagement`. Sem isso, quem plantasse um id de sessão no navegador da
  vítima continuaria dono da sessão depois do login (*session fixation*).
- **CSRF está ligada** (volta automaticamente com `api_only = false`). É a
  defesa principal agora que a autenticação anda em cookie.
- **Prefetch do Turbo não encosta na sessão.** Ver
  `ApplicationController#isolate_prefetch_from_session`. Um prefetch não é uma
  visita — a resposta pode ser descartada —, então ele não consome o flash
  (`flash.keep`) nem responde com `Set-Cookie`
  (`request.session_options[:skip]`). Só o `flash.keep` não resolve: o prefetch
  que partiu antes da mensagem existir sobrescreveria o cookie mais novo.
  O prefetch em si está **desligado** no `<body>`
  (`data-turbo-prefetch="false"`), porque sobra um caminho que o servidor não
  alcança: o Turbo reusa a resposta capturada no hover, e uma página buscada
  antes de o flash existir aparece sem ele. O guard fica como defesa em
  profundidade. Não reative sem reler a seção 5.5 de `docs/ARQUITETURA.md`.
- **`role` nunca vem do cliente.** Está fora dos Strong Parameters. Nenhuma
  autorização depende dele ainda — o campo existe apenas para uso futuro.

## Convenções de front-end
- Criar lista/tarefa é sempre por **popup** (`shared/_modal` + `<dialog>`
  nativo, `dialog_controller.js`). Campo de texto solto no topo da página é
  lido como barra de pesquisa — não volte a esse padrão. Editar continua sendo
  página, com URL própria.
- O popup **reabre sozinho** quando a validação falha: passe
  `open: @registro.errors.any?` para o partial.
- Botões e campos usam as classes de `app/assets/tailwind/application.css`
  (`.btn .btn-primary`, `.field`, `.card`, `.badge`) em vez de repetir a sopa
  de utilitários em cada view.
- Depois de mexer no CSS ou em classe nova numa view:
  `docker compose run --rm app bin/rails tailwindcss:build`. O container roda
  só o servidor, não há watcher.

## Convenções de código
- Siga o Rubocop configurado em `.rubocop.yml` (rails-omakase).
- Nomes de métodos/variáveis em inglês; comentários podem ser em português.
- Controllers finos; regra de negócio em models ou concerns.
- Nada de teste sem asserção.

## Armadilhas conhecidas deste ambiente
Já resolvidas — não reintroduza:

- **bootsnap foi removido de propósito.** Seu cache nativo não abre arquivos sob
  um caminho com acento (`Área de Trabalho`) no Windows e quebra o boot.
- **Binstubs em `bin/` precisam de shebang `#!/usr/bin/env ruby`.** Gerados no
  Windows eles saem com `ruby.exe`, que não existe no container Linux.
- **`spec/rails_helper.rb` força `ENV['RAILS_ENV'] = 'test'`** com atribuição
  incondicional. Com `||=` o `RAILS_ENV=development` do container venceria e a
  suíte rodaria contra o banco de desenvolvimento.
- **Não monte volume nomeado em `/usr/local/bundle`.** Ele sombreia as gems da
  imagem, e um `docker compose build` depois de mexer no `Gemfile` não teria
  efeito nenhum.
- **`.modal-panel` precisa de `m-auto`.** O preflight do Tailwind zera a margem
  de tudo, inclusive o `margin: auto` que centraliza um `<dialog>` modal.
- **As opções do Cuprite vão no `driven_by(options:)`, não em
  `Capybara.register_driver`.** No Rails 8.1 o `:cuprite` está na lista
  `registerable?` do `ActionDispatch::SystemTesting::Driver`, então o
  `driven_by` re-registra o driver e descarta o registro manual. Sem o
  `--no-sandbox` o Chrome não sobe como root e o Ferrum falha com
  "Browser did not produce websocket url".

## Git
- Commits pequenos e descritivos: `tipo: descrição curta`
  (ex.: `feat: adiciona filtro de tarefas concluídas`).
- Nunca reescrever histórico de branches compartilhadas.

## Quando estiver em dúvida
- Pergunte antes de agir em vez de assumir.
- Prefira o caminho mais simples que faz os testes passarem.
