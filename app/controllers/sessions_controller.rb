class SessionsController < ApplicationController
  # Digest descartavel, calculado uma vez no carregamento da classe, com o
  # mesmo custo que o has_secure_password usa.
  DUMMY_PASSWORD_DIGEST = BCrypt::Password.create(
    "senha-que-nunca-autentica",
    cost: ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST : BCrypt::Engine.cost
  ).freeze

  skip_before_action :require_login, only: %i[new create]

  def new
  end

  def create
    user = User.find_by(email: params[:email].to_s.downcase.strip)

    if user&.authenticate(params[:password].to_s)
      start_session_for(user)
      redirect_to lists_path
    else
      waste_password_comparison if user.nil?
      # Mensagem unica de proposito: distinguir "email nao cadastrado" de
      # "senha errada" transformaria o login num oraculo de quais emails
      # existem na base.
      flash.now[:alert] = "Email ou senha invalidos"
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    reset_session
    redirect_to login_path
  end

  private

  # Sem isto, um email inexistente responde bem mais rapido que uma senha
  # errada - nenhum bcrypt chega a rodar -, e essa diferenca de tempo revela
  # quais emails estao cadastrados mesmo com a mensagem sendo identica.
  def waste_password_comparison
    BCrypt::Password.new(DUMMY_PASSWORD_DIGEST).is_password?(params[:password].to_s)
  end
end
