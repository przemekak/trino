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
package io.trino.spi.transaction;

import io.trino.spi.TrinoException;

import static io.trino.spi.StandardErrorCode.UNSUPPORTED_ISOLATION_LEVEL;
import static java.lang.String.format;

public enum IsolationLevel
{
    SERIALIZABLE,
    REPEATABLE_READ,
    READ_COMMITTED,
    READ_UNCOMMITTED;

    public boolean meetsRequirementOf(IsolationLevel requirement)
    {
        return switch (this) {
            case READ_UNCOMMITTED -> requirement == READ_UNCOMMITTED;
            case READ_COMMITTED -> requirement == READ_UNCOMMITTED || requirement == READ_COMMITTED;
            case REPEATABLE_READ -> requirement == READ_UNCOMMITTED || requirement == READ_COMMITTED || requirement == REPEATABLE_READ;
            case SERIALIZABLE -> true;
        };
    }

    @Override
    public String toString()
    {
        return name().replace('_', ' ');
    }

    public static void checkConnectorSupports(IsolationLevel supportedLevel, IsolationLevel requestedLevel)
    {
        if (!supportedLevel.meetsRequirementOf(requestedLevel)) {
            throw new TrinoException(UNSUPPORTED_ISOLATION_LEVEL, format("Connector supported isolation level %s does not meet requested isolation level %s", supportedLevel, requestedLevel));
        }
    }
}
