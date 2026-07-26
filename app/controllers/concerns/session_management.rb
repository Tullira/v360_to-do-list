module SessionManagement
  extend ActiveSupport::Concern

  private

  # reset_session antes de gravar o user_id descarta o identificador de sessao
  # que o visitante trazia. Sem isso, quem conseguisse plantar um id de sessao
  # no navegador da vitima continuaria dono daquela sessao depois do login
  # (session fixation).
  def start_session_for(user)
    reset_session
    session[:user_id] = user.id
  end
end
