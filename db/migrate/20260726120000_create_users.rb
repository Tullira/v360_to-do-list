class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :username, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      # Campo pronto para uso futuro. Nenhuma autorizacao depende dele ainda.
      t.string :role, null: false, default: "user"

      t.timestamps
    end

    # O email e normalizado para minusculas no model, entao um indice simples
    # ja garante unicidade case-insensitive de fato.
    add_index :users, :email, unique: true

    # O username e guardado como digitado, entao a unicidade case-insensitive
    # precisa de um indice funcional - sem ele, duas requisicoes simultaneas
    # criariam "ana" e "Ana" driblando a validacao do model.
    add_index :users, "lower(username)", unique: true, name: "index_users_on_lower_username"
  end
end
