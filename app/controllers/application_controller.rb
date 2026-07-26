class ApplicationController < ActionController::Base
  include SessionManagement

  before_action :require_login

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

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
