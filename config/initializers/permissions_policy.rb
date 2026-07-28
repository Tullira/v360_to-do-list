# A aplicacao nao usa camera, microfone, geolocalizacao, pagamento nem USB.
# Negar todos e de graca e fecha o que um XSS ou um iframe de terceiro poderia
# tentar acessar em nome do usuario, alem do que a CSP ja cobre.
#
# NAO usa `config.permissions_policy`. O helper do Rails 8.1 ainda emite o
# cabecalho antigo `Feature-Policy` - o proprio codigo do actionpack registra
# que "Permissions-Policy requires a different implementation and isn't yet
# supported by Rails". Feature-Policy foi descontinuado e navegador atual o
# ignora, entao aquele caminho entregaria uma protecao que nao existe.
#
# O cabecalho aqui e estatico e igual para toda resposta, entao default_headers
# resolve sem middleware nenhum.
Rails.application.config.action_dispatch.default_headers.merge!(
  "Permissions-Policy" => "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
)
