class UsersController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

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
