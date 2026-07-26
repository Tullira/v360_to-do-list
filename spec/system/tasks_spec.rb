require "rails_helper"

RSpec.describe "Tarefas", type: :system do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }
  let(:list) { create(:list, user: owner, name: "Mercado") }

  before { sign_in(owner) }

  it "mostra o estado vazio quando a lista nao tem tarefas" do
    visit list_path(list)

    expect(page).to have_content("Nenhuma tarefa por aqui")
  end

  it "mostra apenas as tarefas da lista aberta" do
    create(:task, list: list, title: "Comprar leite")
    create(:task, list: create(:list, user: owner), title: "Tarefa de outra lista")

    visit list_path(list)

    expect(page).to have_content("Comprar leite")
    expect(page).not_to have_content("Tarefa de outra lista")
  end

  it "adiciona uma tarefa" do
    visit list_path(list)

    fill_in "Nova tarefa", with: "Comprar leite"
    expect { click_button "Adicionar" }.to change(list.tasks, :count).by(1)

    expect(page).to have_content("Comprar leite")
  end

  it "recusa tarefa sem titulo" do
    visit list_path(list)

    fill_in "Nova tarefa", with: ""
    expect { click_button "Adicionar" }.not_to change(Task, :count)

    expect(page).to have_content("Title can't be blank")
  end

  it "marca uma tarefa como concluida" do
    task = create(:task, list: list, title: "Comprar leite", completed: false)

    visit list_path(list)
    check "Concluida"

    expect(page).to have_css("[data-completed='true']")
    expect(task.reload.completed).to be(true)
  end

  it "edita o titulo de uma tarefa" do
    task = create(:task, list: list, title: "Antigo")

    visit edit_list_task_path(list, task)
    fill_in "Titulo", with: "Novo"
    click_button "Salvar"

    expect(page).to have_content("Novo")
    expect(task.reload.title).to eq("Novo")
  end

  it "guarda descricao e prazo" do
    task = create(:task, list: list)

    visit edit_list_task_path(list, task)
    fill_in "Descricao", with: "Integral, 2 litros"
    fill_in "Prazo", with: "2026-08-01"
    click_button "Salvar"

    expect(task.reload.description).to eq("Integral, 2 litros")
    expect(task.reload.due_date).to eq(Date.new(2026, 8, 1))
  end

  it "remove uma tarefa" do
    create(:task, list: list, title: "Comprar leite")

    visit list_path(list)
    expect { click_button "Excluir tarefa" }.to change(Task, :count).by(-1)

    expect(page).not_to have_content("Comprar leite")
  end

  it "mantem as tarefas apos recarregar a pagina" do
    visit list_path(list)
    fill_in "Nova tarefa", with: "Comprar leite"
    click_button "Adicionar"

    visit list_path(list)

    expect(page).to have_content("Comprar leite")
  end

  it "nao abre as tarefas de uma lista de outro usuario" do
    list_alheia = create(:list, user: other_user)
    create(:task, list: list_alheia, title: "Tarefa alheia")

    visit list_path(list_alheia)

    expect(page).not_to have_content("Tarefa alheia")
    expect(page).to have_content("Recurso nao encontrado")
  end
end
