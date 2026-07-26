class TasksController < ApplicationController
  before_action :set_list
  before_action :set_task, only: %i[show edit update destroy]

  def show
    redirect_to list_path(@list)
  end

  def edit
  end

  def create
    @task = @list.tasks.build(task_params)

    if @task.save
      redirect_to list_path(@list)
    else
      @tasks = @list.tasks.order(:created_at)
      render "lists/show", status: :unprocessable_content
    end
  end

  def update
    if @task.update(task_params)
      redirect_to list_path(@list)
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @task.destroy
    redirect_to list_path(@list)
  end

  private

  # A posse de uma task e sempre verificada via list.user_id - aqui, pelo
  # escopo current_user.lists. Lista alheia vira 404, nao 403.
  def set_list
    @list = current_user.lists.find(params[:list_id])
  end

  # Escopado em @list: id de tarefa de outra lista resulta em 404.
  def set_task
    @task = @list.tasks.find(params[:id])
  end

  # list_id fora da lista permitida: a lista vem sempre da rota, ja validada
  # como do current_user. Aceita-lo permitiria criar uma task na lista de
  # outro usuario ou mover uma task para fora do escopo.
  def task_params
    params.require(:task).permit(:title, :description, :completed, :due_date)
  end
end
