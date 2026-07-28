class ListsController < ApplicationController
  before_action :set_list, only: %i[show edit update destroy]

  def index
    @lists = lists_with_counts
    @list = List.new
  end

  def show
    @tasks = @list.tasks.order(:created_at)
    @task = Task.new
  end

  def edit
  end

  def create
    @list = current_user.lists.build(list_params)

    if @list.save
      redirect_to lists_path
    else
      @lists = lists_with_counts
      render :index, status: :unprocessable_content
    end
  end

  def update
    if @list.update(list_params)
      redirect_to list_path(@list)
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @list.destroy
    redirect_to lists_path
  end

  private

  # Os dois contadores vem agregados do banco. Antes eram calculados em Ruby
  # (`list.tasks.size` e `list.tasks.count(&:completed?)`), o que obrigava a
  # carregar TODAS as tarefas de TODAS as listas na memoria a cada acesso a
  # home so para exibir dois numeros por linha.
  #
  # COUNT(...) FILTER e sintaxe do Postgres, que e o unico banco do projeto.
  def lists_with_counts
    current_user.lists
                .left_joins(:tasks)
                .select("lists.*",
                        "COUNT(tasks.id) AS tasks_count",
                        "COUNT(tasks.id) FILTER (WHERE tasks.completed) AS completed_count")
                .group("lists.id")
                .order(created_at: :desc)
  end

  # Busca escopada em current_user.lists: lista de outro usuario levanta
  # RecordNotFound e vira 404, indistinguivel de uma lista inexistente.
  def set_list
    @list = current_user.lists.find(params[:id])
  end

  # user_id fora da lista permitida: o dono vem sempre da sessao, nunca do
  # payload - senao daria para criar ou transferir lista para outro usuario.
  def list_params
    params.require(:list).permit(:name)
  end
end
