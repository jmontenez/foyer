using Npgsql;
using NpgsqlTypes;
using System.Text.Json;
namespace Foyer;

public sealed class Store(NpgsqlDataSource source, IHttpContextAccessor accessor)
{
    public async Task Initialize()
    {
        await using var cmd = source.CreateCommand("CREATE TABLE IF NOT EXISTS foyer_state (id integer PRIMARY KEY CHECK(id=1), data jsonb NOT NULL); INSERT INTO foyer_state(id,data) VALUES(1,@data) ON CONFLICT DO NOTHING");
        cmd.Parameters.AddWithValue("data", NpgsqlDbType.Jsonb, JsonSerializer.Serialize(new Household(), Defaults.Json));
        await cmd.ExecuteNonQueryAsync();
    }
    // One household aggregate, locked transactionally: predictable concurrency for two users.
    // No credentials or session hashes ever leave this repository through public DTOs.
    public async Task<T> Read<T>(Func<Household, T> action)
    {
        await using var cmd = source.CreateCommand("SELECT data::text FROM foyer_state WHERE id=1");
        var raw = (string?)await cmd.ExecuteScalarAsync() ?? throw new InvalidOperationException("Database not initialized");
        return action(JsonSerializer.Deserialize<Household>(raw, Defaults.Json)!);
    }
    public async Task<T> Update<T>(Func<Household, T> action)
    {
        await using var connection = await source.OpenConnectionAsync();
        await using var tx = await connection.BeginTransactionAsync();
        await using var read = new NpgsqlCommand("SELECT data::text FROM foyer_state WHERE id=1 FOR UPDATE", connection, tx);
        var h = JsonSerializer.Deserialize<Household>((string)(await read.ExecuteScalarAsync())!, Defaults.Json)!;
        var http = accessor.HttpContext;
        if (http is not null && http.Request.Path.StartsWithSegments("/api/v1"))
        {
            Security.Member(http, h); // Recheck revocation inside the transaction, not just before it.
            if (h.Maintenance) throw new RuleException("Maintenance en cours.", 503);
        }
        var result = action(h); h.Revision++;
        await using var write = new NpgsqlCommand("UPDATE foyer_state SET data=@data WHERE id=1", connection, tx);
        write.Parameters.AddWithValue("data", NpgsqlDbType.Jsonb, JsonSerializer.Serialize(h, Defaults.Json));
        await write.ExecuteNonQueryAsync(); await tx.CommitAsync(); return result;
    }
}
