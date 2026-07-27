require "rails_helper"

RSpec.describe "Listas", type: :system do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  before { sign_in(owner) }

  it "mostra apenas as listas do usuario logado" do
    create(:list, user: owner, name: "Mercado")
    create(:list, user: other_user, name: "Lista alheia")

    visit lists_path

    expect(page).to have_content("Mercado")
    expect(page).not_to have_content("Lista alheia")
  end

  it "mostra o estado vazio quando nao ha listas" do
    visit lists_path

    expect(page).to have_content("Voce ainda nao tem listas")
  end

  it "so mostra o campo de nome depois de abrir o popup" do
    visit lists_path

    # Um campo solto na pagina parece barra de pesquisa. O formulario de
    # criacao so existe dentro do popup, aberto de proposito pelo usuario.
    expect(page).not_to have_field("Nome da lista")

    click_button "Nova lista"

    expect(page).to have_field("Nome da lista")
  end

  it "cria uma lista pelo popup" do
    visit lists_path

    click_button "Nova lista"
    fill_in "Nome da lista", with: "Mercado"
    click_button "Criar lista"

    # A asserção de tela vem antes da do banco de propósito: ela é a que
    # espera. Ver o comentário em spec/system/authentication_spec.rb.
    expect(page).to have_content("Mercado")
    expect(owner.lists.count).to eq(1)
  end

  it "reabre o popup com o erro quando o nome vem vazio" do
    visit lists_path

    click_button "Nova lista"
    fill_in "Nome da lista", with: ""
    click_button "Criar lista"

    expect(page).to have_content("Name can't be blank")
    # O popup nao pode fechar levando junto o que a pessoa digitou.
    expect(page).to have_field("Nome da lista")
    expect(List.count).to eq(0)
  end

  it "fecha o popup ao cancelar" do
    visit lists_path

    click_button "Nova lista"
    click_button "Cancelar"

    expect(page).not_to have_field("Nome da lista")
  end

  it "renomeia uma lista" do
    list = create(:list, user: owner, name: "Antigo")

    visit edit_list_path(list)
    fill_in "Nome da lista", with: "Novo"
    click_button "Salvar"

    expect(page).to have_content("Novo")
    expect(list.reload.name).to eq("Novo")
  end

  it "remove uma lista" do
    create(:list, user: owner, name: "Mercado")

    visit lists_path
    click_button "Excluir"

    expect(page).not_to have_content("Mercado")
    expect(List.count).to eq(0)
  end

  it "nao abre a lista de outro usuario" do
    list = create(:list, user: other_user, name: "Lista alheia")

    visit list_path(list)

    expect(page).not_to have_content("Lista alheia")
    expect(page).to have_content("Recurso nao encontrado")
  end

  it "nao abre a edicao da lista de outro usuario" do
    list = create(:list, user: other_user)

    visit edit_list_path(list)

    expect(page).to have_content("Recurso nao encontrado")
  end
end
