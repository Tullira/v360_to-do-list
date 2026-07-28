# O layout ja chamava csp_meta_tag, mas sem politica configurada o helper nao
# emite nada e nenhum cabecalho Content-Security-Policy era enviado.
#
# Hoje o escapamento automatico do ERB segura o XSS - nao ha um unico html_safe
# em app/ -, mas isso e uma linha de defesa so. Sem CSP, um XSS futuro nao fica
# contido pelo httponly: o atacante nao rouba o cookie, mas age como o usuario
# e exfiltra dados via fetch() para um dominio externo.
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
    # Substitui o X-Frame-Options em navegador moderno.
    policy.frame_ancestors :none
  end

  # Nonce POR SESSAO, nao por requisicao, e guardado explicitamente na sessao.
  #
  # Por sessao porque duas respostas precisam ser identicas byte a byte:
  # recurso alheio vs. inexistente (404) e senha errada vs. e-mail inexistente
  # (login). Um nonce sorteado a cada render faria as duas diferirem e
  # devolveria justamente o canal de enumeracao que esses dois casos existem
  # para fechar.
  #
  # E guardado aqui em vez de usar `request.session.id` porque o id da sessao e
  # nil enquanto nada foi gravado nela. Isso produzia nonce vazio - o
  # <meta name="csp-nonce"> saia sem valor e o <script type="importmap">, que e
  # inline, seria bloqueado no primeiro acesso de qualquer visitante. Pior: o
  # valor passava a existir ou nao conforme a requisicao anterior tivesse
  # gravado sessao, o que reintroduzia a diferenca entre as duas respostas.
  #
  # O ||= grava na primeira renderizacao e o valor sobrevive pela sessao
  # inteira; reset_session (login e logout) sorteia outro.
  config.content_security_policy_nonce_generator = lambda do |request|
    request.session[:csp_nonce] ||= SecureRandom.base64(16)
  end

  # style-src tambem recebe nonce, alem de script-src: o Turbo injeta em tempo
  # de execucao o <style> da barra de progresso, lendo o nonce do
  # <meta name="csp-nonce"> que o csp_meta_tag emite. Sem isso a alternativa
  # seria 'unsafe-inline' em style-src.
  config.content_security_policy_nonce_directives = %w[script-src style-src]

  # report_only em desenvolvimento: o console lista o que quebraria antes de a
  # politica passar a bloquear de verdade.
  config.content_security_policy_report_only = Rails.env.development?
end
