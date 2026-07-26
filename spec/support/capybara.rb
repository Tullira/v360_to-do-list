require "capybara/rspec"
require "capybara/cuprite"

Capybara.default_max_wait_time = 5

# ATENCAO: nao registre o driver :cuprite com Capybara.register_driver aqui.
# No Rails 8.1 o :cuprite entrou na lista de drivers "registerable" do
# ActionDispatch::SystemTesting::Driver, entao o driven_by RE-REGISTRA o
# driver e descarta qualquer registro nosso. As opcoes precisam ir pelo
# driven_by(options:) - ver spec/rails_helper.rb.
