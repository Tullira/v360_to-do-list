# expire_after e uma instrucao ao NAVEGADOR: util, mas o cliente pode ignora-la
# ou reescrever o atributo Expires do cookie. A validade que vale de verdade e
# conferida no servidor, a partir do carimbo assinado dentro do proprio cookie
# (ver SessionManagement#session_expired?).
#
# secure so em producao: em desenvolvimento e teste a aplicacao responde em
# HTTP puro e um cookie Secure nunca seria enviado de volta.
Rails.application.config.session_store :cookie_store,
  key: "_to_do_list_session",
  expire_after: 2.weeks,
  same_site: :lax,
  httponly: true,
  secure: Rails.env.production?
