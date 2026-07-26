module AuthHelpers
  # Senha padrao da factory :user.
  DEFAULT_PASSWORD = "senha_super_secreta".freeze

  # Specs de sistema: autentica pelo formulario, como um usuario de verdade.
  def sign_in(user, password: DEFAULT_PASSWORD)
    visit login_path
    fill_in "Email", with: user.email
    fill_in "Senha", with: password
    click_button "Entrar"
  end

  # Specs de request: autentica pela rota, para exercitar params forjados que
  # um navegador nao conseguiria enviar.
  def sign_in_via_request(user, password: DEFAULT_PASSWORD)
    post login_path, params: { email: user.email, password: password }
  end
end
