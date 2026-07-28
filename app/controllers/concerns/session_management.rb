module SessionManagement
  extend ActiveSupport::Concern

  # Prazo de validade da sessao. Combina com o expire_after de
  # config/initializers/session_store.rb, mas quem manda e este: o do cookie
  # depende da boa vontade do cliente.
  SESSION_MAX_AGE = 2.weeks

  private

  # reset_session antes de gravar o user_id descarta o identificador de sessao
  # que o visitante trazia. Sem isso, quem conseguisse plantar um id de sessao
  # no navegador da vitima continuaria dono daquela sessao depois do login
  # (session fixation).
  def start_session_for(user)
    reset_session
    session[:user_id] = user.id
    # Carimbo assinado junto com o resto da sessao: o cliente nao consegue
    # adiar a expiracao sem invalidar a assinatura do cookie inteiro.
    session[:created_at] = Time.current.to_i
  end

  # Sessao sem carimbo tambem expira. Sao os cookies emitidos antes desta
  # correcao: falhar fechado obriga um login novo em vez de conceder validade
  # eterna a quem chegou primeiro.
  def session_expired?
    created_at = session[:created_at]

    created_at.blank? || Time.at(created_at) < SESSION_MAX_AGE.ago
  end
end
