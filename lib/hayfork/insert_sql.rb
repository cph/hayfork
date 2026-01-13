module Hayfork
  class InsertSql
    attr_reader :haystack, :relation, :bindings

    def initialize(haystack, relation, bindings)
      @haystack = haystack
      @relation = relation
      @bindings = bindings
    end

    def to_sql(from: true, by_row: false)
      select_statement = relation.select(bindings.map(&:to_s))
      if from
        select_statement = by_row ?
          select_statement.from("(SELECT NEW.*) \"#{relation.table_name}\"") :
          select_statement.from("new_table \"#{relation.table_name}\"")
      end

      <<~SQL
        INSERT INTO #{haystack.table_name} (#{bindings.map(&:key).join(", ")}) SELECT * FROM (#{select_statement.to_sql}) "x" WHERE "x"."#{Hayfork::TEXT}" != '';
      SQL
    end
    alias to_s to_sql

  end
end
