class ApplicationController < ActionController::Base
  include SessionManagement

  before_action :isolate_prefetch_from_session
  before_action :require_login

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  # O Turbo faz prefetch do link assim que o mouse passa por cima dele, em
  # paralelo com a navegacao real. Um prefetch nao e uma visita - a resposta
  # pode ser descartada - entao ele nao pode mexer na sessao:
  #
  #   flash.keep            impede que ele leia e apague a mensagem;
  #   session_options[:skip] impede que ele responda com Set-Cookie. Sem isso a
  #                   sessao que ele carregava (buscada antes de a mensagem
  #                   existir) sobrescreve a mais nova, e o flash some igual.
  #
  # O cabecalho vem do cliente, entao ele so vale onde prefetch de fato existe:
  # navegacao, que e sempre GET (ou HEAD). Aceita-lo em POST/DELETE deixaria
  # qualquer requisicao desligar a gravacao da sessao - e um logout que nao
  # responde Set-Cookie roda o reset_session no servidor mas deixa o cookie
  # antigo valido no navegador, ou seja, nao desloga ninguem.
  def isolate_prefetch_from_session
    return unless request.get? || request.head?
    return unless request.headers["X-Sec-Purpose"] == "prefetch"

    flash.keep
    request.session_options[:skip] = true
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
  helper_method :current_user

  def signed_in?
    current_user.present?
  end
  helper_method :signed_in?

  def require_login
    return if signed_in?

    redirect_to login_path, alert: "Faca login para continuar"
  end

  # Recurso de outro usuario cai aqui pelo escopo em current_user.lists e
  # responde 404, igual a recurso inexistente. Um 403 confirmaria que aquele
  # id existe e permitiria enumerar os recursos alheios.
  def render_not_found
    render "shared/not_found", status: :not_found
  end
end
