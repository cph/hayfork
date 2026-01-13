module Hayfork
  class Triggers
    attr_reader :haystack

    def initialize(haystack, by_row: false)
      @haystack = haystack
      @by_row = by_row
      @_triggers = []
    end

    def <<(trigger)
      _triggers << trigger
    end

    def create
      _triggers.map { |args| psql_create_triggers_for(*args) }.join
    end

    def drop
      _triggers.map { |model, _, options| psql_drop_triggers_for(model, options) }.join
    end

    def replace
      [drop, create].join
    end

    def truncate
      "TRUNCATE #{haystack.table_name};\n"
    end

    def rebuild
      ([truncate] + _triggers.map { |args| psql_inserts_for(*args) }).join
    end

    def by_row?
      @by_row
    end

  private
    attr_reader :_triggers

    def psql_create_triggers_for(model, statements, options)
      name = function_name(model, options)
      <<~SQL
        CREATE FUNCTION #{name}() RETURNS trigger AS $$
        BEGIN
          IF TG_OP = 'DELETE' THEN
            #{statements.to_delete_sql(by_row: by_row?)}
            RETURN OLD;
          ELSIF TG_OP = 'UPDATE' THEN
            #{statements.to_update_sql(by_row: by_row?)}
            RETURN NEW;
          ELSIF TG_OP = 'INSERT' THEN
            #{statements.to_insert_sql(by_row: by_row?)}
            RETURN NEW;
          END IF;
          RETURN NULL; -- result is ignored since this is an AFTER trigger
        END;
        $$ LANGUAGE plpgsql;
        #{by_row? ? psql_row_trigger(model, name).strip : psql_statement_triggers(model, name).strip}
      SQL
    end

    def psql_inserts_for(model, statements, options)
      "#{statements.to_insert_sql(from: false, by_row: by_row?)}\n" if options.fetch(:rebuild, true)
    end

    def psql_drop_triggers_for(model, options)
      name = function_name(model, options)
      <<~SQL
        DROP FUNCTION IF EXISTS #{name}() CASCADE;
      SQL
    end

    def psql_statement_triggers(model, name)
      <<~SQL
        CREATE TRIGGER #{name}_insert_trigger AFTER INSERT ON #{model.table_name}
          REFERENCING NEW TABLE AS new_table
          FOR EACH STATEMENT EXECUTE PROCEDURE #{name}();
        CREATE TRIGGER #{name}_update_trigger AFTER UPDATE ON #{model.table_name}
          REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table
          FOR EACH STATEMENT EXECUTE PROCEDURE #{name}();
        CREATE TRIGGER #{name}_delete_trigger AFTER DELETE ON #{model.table_name}
          REFERENCING OLD TABLE AS old_table
          FOR EACH STATEMENT EXECUTE PROCEDURE #{name}();
      SQL
    end

    def psql_row_trigger(model, name)
      <<~SQL
        CREATE TRIGGER #{name}_trigger BEFORE INSERT OR UPDATE OR DELETE ON #{model.table_name}
          FOR EACH ROW EXECUTE PROCEDURE #{name}();
      SQL
    end

    def function_name(model, options)
      options.fetch(:name, "maintain_#{model.table_name}_in_#{haystack.table_name}")
    end

  end
end
