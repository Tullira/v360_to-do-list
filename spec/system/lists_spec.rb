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

  it "cria uma lista" do
    visit lists_path

    fill_in "Nome da lista", with: "Mercado"
    expect { click_button "Criar lista" }.to change(owner.lists, :count).by(1)

    expect(page).to have_content("Mercado")
  end

  it "recusa lista sem nome" do
    visit lists_path

    fill_in "Nome da lista", with: ""
    expect { click_button "Criar lista" }.not_to change(List, :count)

    expect(page).to have_content("Name can't be blank")
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
    expect { click_button "Excluir" }.to change(List, :count).by(-1)

    expect(page).not_to have_content("Mercado")
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
