require "rails_helper"

RSpec.describe "Autenticacao", type: :system do
  describe "cadastro" do
    it "cria a conta e ja deixa o usuario logado" do
      visit signup_path

      fill_in "Usuario", with: "ana"
      fill_in "Email", with: "ana@example.com"
      fill_in "Senha", with: "senha_super_secreta"
      fill_in "Confirme a senha", with: "senha_super_secreta"

      click_button "Criar conta"

      # Sincronize com a resposta antes de olhar o banco. O Turbo envia o
      # formulario por fetch, entao nao ha navegacao para o Capybara esperar:
      # click_button volta na hora e `change(User, :count)` - que nao tem
      # retry - leria o contador antes de o POST terminar.
      expect(page).to have_content("Minhas listas")
      expect(page).to have_button("Sair")
      expect(User.count).to eq(1)
    end

    it "mostra erro quando o email ja esta cadastrado" do
      create(:user, email: "ana@example.com")

      visit signup_path
      fill_in "Usuario", with: "outra"
      fill_in "Email", with: "ana@example.com"
      fill_in "Senha", with: "senha_super_secreta"
      fill_in "Confirme a senha", with: "senha_super_secreta"
      click_button "Criar conta"

      expect(page).to have_content("Email has already been taken")
      expect(page).to have_button("Criar conta")
    end

    it "mostra erro quando o usuario ja esta cadastrado" do
      create(:user, username: "ana")

      visit signup_path
      fill_in "Usuario", with: "ana"
      fill_in "Email", with: "outra@example.com"
      fill_in "Senha", with: "senha_super_secreta"
      fill_in "Confirme a senha", with: "senha_super_secreta"
      click_button "Criar conta"

      expect(page).to have_content("Username has already been taken")
    end

    it "mostra erro quando a senha e curta demais" do
      visit signup_path
      fill_in "Usuario", with: "ana"
      fill_in "Email", with: "ana@example.com"
      fill_in "Senha", with: "curta12"
      fill_in "Confirme a senha", with: "curta12"
      click_button "Criar conta"

      expect(page).to have_content("Password is too short")
    end

    # V-06: sem recuperacao de senha no projeto, um erro de digitacao sem
    # confirmacao trancaria a conta para sempre.
    it "mostra erro quando a confirmacao da senha nao bate" do
      visit signup_path
      fill_in "Usuario", with: "ana"
      fill_in "Email", with: "ana@example.com"
      fill_in "Senha", with: "senha_super_secreta"
      fill_in "Confirme a senha", with: "senha_diferente_1"
      click_button "Criar conta"

      expect(page).to have_content("Password confirmation doesn't match Password")
      expect(User.count).to eq(0)
    end

    it "recusa uma senha comum demais" do
      visit signup_path
      fill_in "Usuario", with: "ana"
      fill_in "Email", with: "ana@example.com"
      fill_in "Senha", with: "password1"
      fill_in "Confirme a senha", with: "password1"
      click_button "Criar conta"

      expect(page).to have_content("facil demais de adivinhar")
      expect(User.count).to eq(0)
    end
  end

  describe "login" do
    let!(:user) { create(:user, email: "ana@example.com") }

    it "entra com as credenciais corretas" do
      sign_in(user)

      expect(page).to have_content("Minhas listas")
      expect(page).to have_button("Sair")
    end

    it "recusa senha errada" do
      sign_in(user, password: "senha_errada_1")

      expect(page).to have_content("Email ou senha invalidos")
      expect(page).to have_button("Entrar")
    end

    it "recusa email inexistente com a mesma mensagem da senha errada" do
      visit login_path
      fill_in "Email", with: "ninguem@example.com"
      fill_in "Senha", with: "qualquer_senha"
      click_button "Entrar"

      # Mensagem identica a da senha errada: distinguir os dois casos
      # revelaria quais emails existem na base.
      expect(page).to have_content("Email ou senha invalidos")
    end

    it "aceita o email com caixa diferente da cadastrada" do
      visit login_path
      fill_in "Email", with: "ANA@Example.com"
      fill_in "Senha", with: AuthHelpers::DEFAULT_PASSWORD
      click_button "Entrar"

      expect(page).to have_content("Minhas listas")
    end
  end

  describe "logout" do
    it "encerra a sessao e volta a exigir login" do
      sign_in(create(:user))
      expect(page).to have_content("Minhas listas")

      click_button "Sair"

      expect(page).to have_button("Entrar")

      visit lists_path
      expect(page).to have_content("Faca login para continuar")
    end
  end

  describe "visitante" do
    it "e mandado para o login ao tentar abrir as listas" do
      visit lists_path

      expect(page).to have_current_path(login_path)
      expect(page).to have_content("Faca login para continuar")
    end

    it "e mandado para o login ao tentar abrir uma lista especifica" do
      list = create(:list)

      visit list_path(list)

      expect(page).to have_current_path(login_path)
    end
  end
end
