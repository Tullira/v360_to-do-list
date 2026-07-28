class UsersController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  # Sem isto, criar contas e gratis para o atacante e caro para a droplet:
  # cada cadastro custa um bcrypt e uma linha no Postgres.
  rate_limit to: 5, within: 1.hour, only: :create, with: -> {
    # O `with:` roda como before_action e interrompe a cadeia, entao a action
    # `new` nunca executa: sem montar o @user aqui, o form_with da view recebe
    # nil e a resposta de bloqueio quebra com erro 500.
    @user = User.new
    flash.now[:alert] = "Muitos cadastros a partir deste endereco. Tente mais tarde."
    render :new, status: :too_many_requests
  }

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      start_session_for(@user)
      redirect_to lists_path
    else
      render :new, status: :unprocessable_content
    end
  # O indice unico do banco e a fonte de verdade; `validates :uniqueness` e uma
  # cortesia de UX que faz SELECT antes do INSERT e perde a corrida entre dois
  # cadastros simultaneos. Sem este rescue a corrida vira 500 - um erro que
  # qualquer visitante consegue disparar.
  rescue ActiveRecord::RecordNotUnique
    @user.errors.add(:email, "ja esta em uso")
    render :new, status: :unprocessable_content
  end

  private

  # role fora da lista permitida: senao o proprio cliente escolheria o papel
  # dele no cadastro.
  def user_params
    params.require(:user).permit(:username, :email, :password, :password_confirmation)
  end
end
