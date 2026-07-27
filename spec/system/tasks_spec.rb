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

  describe "criacao pelo popup" do
    it "so mostra o formulario depois de abrir o popup" do
      visit list_path(list)

      expect(page).not_to have_field("Titulo")

      click_button "Nova tarefa"

      expect(page).to have_field("Titulo")
    end

    it "pede a descricao junto com o titulo" do
      visit list_path(list)

      click_button "Nova tarefa"
      fill_in "Titulo", with: "Comprar leite"
      fill_in "Descricao", with: "Integral, 2 litros"
      click_button "Adicionar"

      # A asserção de tela vem antes da do banco de propósito: ela é a que
      # espera. Ver o comentário em spec/system/authentication_spec.rb.
      expect(page).to have_content("Comprar leite")
      expect(list.tasks.count).to eq(1)
      expect(list.tasks.last.description).to eq("Integral, 2 litros")
    end

    it "aceita prazo na criacao" do
      visit list_path(list)

      click_button "Nova tarefa"
      fill_in "Titulo", with: "Comprar leite"
      fill_in "Prazo", with: "2026-08-01"
      click_button "Adicionar"

      expect(page).to have_content("Comprar leite")
      expect(list.tasks.last.due_date).to eq(Date.new(2026, 8, 1))
    end

    it "reabre o popup com o erro quando o titulo vem vazio" do
      visit list_path(list)

      click_button "Nova tarefa"
      fill_in "Titulo", with: ""
      click_button "Adicionar"

      expect(page).to have_content("Title can't be blank")
      expect(page).to have_field("Titulo")
      expect(Task.count).to eq(0)
    end

    it "mantem as tarefas apos recarregar a pagina" do
      visit list_path(list)
      click_button "Nova tarefa"
      fill_in "Titulo", with: "Comprar leite"
      click_button "Adicionar"
      expect(page).to have_content("Comprar leite")

      visit list_path(list)

      expect(page).to have_content("Comprar leite")
    end
  end

  describe "tela da tarefa" do
    it "abre pelo titulo na lista" do
      task = create(:task, list: list, title: "Comprar leite",
                    description: "Integral, 2 litros", due_date: Date.new(2026, 8, 1))

      visit list_path(list)
      click_link "Comprar leite"

      expect(page).to have_current_path(list_task_path(list, task))
      expect(page).to have_content("Comprar leite")
      expect(page).to have_content("Integral, 2 litros")
    end

    it "avisa quando a tarefa nao tem descricao" do
      task = create(:task, list: list, description: nil)

      visit list_task_path(list, task)

      expect(page).to have_content("Sem descricao")
    end

    it "mostra o estado da tarefa" do
      task = create(:task, list: list, completed: false)

      visit list_task_path(list, task)

      expect(page).to have_css("[data-task-status='pending']")
    end

    it "conclui a tarefa sem sair da tela" do
      task = create(:task, list: list, completed: false)

      visit list_task_path(list, task)
      check "Concluida"

      expect(page).to have_css("[data-task-status='completed']")
      expect(page).to have_current_path(list_task_path(list, task))
      expect(task.reload.completed).to be(true)
    end

    it "volta para a lista" do
      task = create(:task, list: list)

      visit list_task_path(list, task)
      click_link "Mercado"

      expect(page).to have_current_path(list_path(list))
    end

    it "nao abre a tarefa de uma lista de outro usuario" do
      list_alheia = create(:list, user: other_user)
      task = create(:task, list: list_alheia, title: "Tarefa alheia")

      visit list_task_path(list_alheia, task)

      expect(page).not_to have_content("Tarefa alheia")
      expect(page).to have_content("Recurso nao encontrado")
    end
  end

  it "marca uma tarefa como concluida pela lista" do
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

  it "guarda descricao e prazo na edicao" do
    task = create(:task, list: list)

    visit edit_list_task_path(list, task)
    fill_in "Descricao", with: "Integral, 2 litros"
    fill_in "Prazo", with: "2026-08-01"
    click_button "Salvar"

    expect(page).to have_content("Integral, 2 litros")
    expect(task.reload.description).to eq("Integral, 2 litros")
    expect(task.reload.due_date).to eq(Date.new(2026, 8, 1))
  end

  it "remove uma tarefa" do
    create(:task, list: list, title: "Comprar leite")

    visit list_path(list)
    click_button "Excluir tarefa"

    expect(page).not_to have_content("Comprar leite")
    expect(Task.count).to eq(0)
  end

  it "nao abre as tarefas de uma lista de outro usuario" do
    list_alheia = create(:list, user: other_user)
    create(:task, list: list_alheia, title: "Tarefa alheia")

    visit list_path(list_alheia)

    expect(page).not_to have_content("Tarefa alheia")
    expect(page).to have_content("Recurso nao encontrado")
  end
end
