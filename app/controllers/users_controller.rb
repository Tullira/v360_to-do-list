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
  end

  private

  # role fora da lista permitida: senao o proprio cliente escolheria o papel
  # dele no cadastro.
  def user_params
    params.require(:user).permit(:username, :email, :password)
  end
end
