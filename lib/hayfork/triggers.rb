module Hayfork
  class Triggers
    attr_reader :haystack

    def initialize(haystack)
      @haystack = haystack
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

  private
    attr_reader :_triggers

    def psql_create_triggers_for(model, statements, options)
      name = function_name(model, options)
      <<~SQL
        CREATE FUNCTION #{name}() RETURNS trigger AS $$
        BEGIN
          IF TG_OP = 'DELETE' THEN
            #{statements.to_delete_sql}
            RETURN OLD;
          ELSIF TG_OP = 'UPDATE' THEN
            #{statements.to_update_sql}
            RETURN NEW;
          ELSIF TG_OP = 'INSERT' THEN
            #{statements.to_insert_sql}
            RETURN NEW;
          END IF;
          RETURN NULL; -- result is ignored since this is an AFTER trigger
        END;
        $$ LANGUAGE plpgsql;
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

    def psql_inserts_for(model, statements, options)
      "#{statements.to_insert_sql(from: false)}\n" if options.fetch(:rebuild, true)
    end

    def psql_drop_triggers_for(model, options)
      name = function_name(model, options)
      <<~SQL
        DROP FUNCTION IF EXISTS #{name}() CASCADE;
      SQL
    end

    def function_name(model, options)
      options.fetch(:name, "maintain_#{model.table_name}_in_#{haystack.table_name}")
    end

  end
end
