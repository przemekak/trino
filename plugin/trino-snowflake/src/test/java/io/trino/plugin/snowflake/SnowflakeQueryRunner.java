/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package io.trino.plugin.snowflake;

import com.google.common.collect.ImmutableList;
import com.google.common.collect.ImmutableMap;
import io.airlift.log.Logger;
import io.trino.Session;
import io.trino.plugin.tpch.TpchPlugin;
import io.trino.testing.DistributedQueryRunner;
import io.trino.tpch.TpchTable;

import java.util.HashMap;
import java.util.Map;

import static io.airlift.testing.Closeables.closeAllSuppress;
import static io.trino.plugin.tpch.TpchMetadata.TINY_SCHEMA_NAME;
import static io.trino.testing.QueryAssertions.copyTpchTables;
import static io.trino.testing.TestingSession.testSessionBuilder;

public final class SnowflakeQueryRunner
{
    public static final String TPCH_SCHEMA = "tpch";

    private SnowflakeQueryRunner() {}

    public static DistributedQueryRunner createSnowflakeQueryRunner(
            Map<String, String> extraProperties,
            Map<String, String> connectorProperties,
            Iterable<TpchTable<?>> tables)
            throws Exception
    {
        DistributedQueryRunner queryRunner = DistributedQueryRunner.builder(createSession())
                .setExtraProperties(extraProperties)
                .build();
        try {
            queryRunner.installPlugin(new TpchPlugin());
            queryRunner.createCatalog("tpch", "tpch");

            connectorProperties = new HashMap<>(ImmutableMap.copyOf(connectorProperties));
            connectorProperties.putIfAbsent("connection-url", TestingSnowflakeServer.TEST_URL);
            connectorProperties.putIfAbsent("connection-user", TestingSnowflakeServer.TEST_USER);
            connectorProperties.putIfAbsent("connection-password", TestingSnowflakeServer.TEST_PASSWORD);
            connectorProperties.putIfAbsent("snowflake.database", TestingSnowflakeServer.TEST_DATABASE);
            connectorProperties.putIfAbsent("snowflake.role", TestingSnowflakeServer.TEST_ROLE);
            connectorProperties.putIfAbsent("snowflake.warehouse", TestingSnowflakeServer.TEST_WAREHOUSE);

            queryRunner.installPlugin(new SnowflakePlugin());
            queryRunner.createCatalog("snowflake", "snowflake", connectorProperties);

            queryRunner.execute(createSession(), "CREATE SCHEMA IF NOT EXISTS " + TPCH_SCHEMA);
            copyTpchTables(queryRunner, "tpch", TINY_SCHEMA_NAME, tables);

            return queryRunner;
        }
        catch (Throwable e) {
            closeAllSuppress(e, queryRunner);
            throw e;
        }
    }

    public static Session createSession()
    {
        return testSessionBuilder()
                .setCatalog("snowflake")
                .setSchema(TPCH_SCHEMA)
                .build();
    }

    public static void main(String[] args)
            throws Exception
    {
        DistributedQueryRunner queryRunner = createSnowflakeQueryRunner(
                ImmutableMap.of("http-server.http.port", "8080"),
                ImmutableMap.of(),
                ImmutableList.of());

        Logger log = Logger.get(SnowflakeQueryRunner.class);
        log.info("======== SERVER STARTED ========");
        log.info("\n====\n%s\n====", queryRunner.getCoordinator().getBaseUrl());
    }
}
