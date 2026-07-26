class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      # Sem user_id: a posse de uma task e sempre derivada de list.user_id.
      t.references :list, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.boolean :completed, null: false, default: false
      t.date :due_date

      t.timestamps
    end
  end
end
