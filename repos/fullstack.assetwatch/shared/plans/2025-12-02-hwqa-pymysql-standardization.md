# HWQA PyMySQL Standardization Plan

## Overview

Convert HWQA database code from mysql.connector-compatible syntax to native pymysql syntax, removing the `ConnectionWrapper` compatibility layer and aligning with assetwatch database patterns.

## Current State Analysis

The HWQA code **already uses pymysql** via the `db_resources` layer. However, it wraps pymysql in a `ConnectionWrapper` class that translates mysql.connector syntax (`cursor(dictionary=True)`) to pymysql syntax (`cursor(pymysql.cursors.DictCursor)`).

### Key Discoveries:
- `lambdas/lf-vero-prod-hwqa/app/database/connection.py` contains `ConnectionWrapper` class (lines 22-61)
- All 12 route files use `cursor(dictionary=True)` mysql.connector syntax
- The `DatabaseConnection` class already delegates to `db_resources.get_connection()`
- No actual mysql.connector imports exist - it's purely a syntax compatibility layer

### Files Using mysql.connector Syntax:
1. `app/middleware.py`
2. `app/routes/auth_routes.py`
3. `app/routes/bulk_test_routes.py`
4. `app/routes/glossary_routes.py`
5. `app/routes/hub_dashboard_routes.py`
6. `app/routes/hub_shipment_routes.py`
7. `app/routes/hub_test_routes.py`
8. `app/routes/sensor_conversion_routes.py`
9. `app/routes/sensor_dashboard_routes.py`
10. `app/routes/sensor_shipment_routes.py`
11. `app/routes/sensor_test_routes.py`
12. `app/routes/shared_dashboard_routes.py`

## Desired End State

- All HWQA database code uses native pymysql cursor syntax: `cursor(pymysql.cursors.DictCursor)`
- The `ConnectionWrapper` class is removed
- The `DatabaseConnection` class is simplified to expose the raw pymysql connection
- Code patterns match the rest of assetwatch lambdas

### Verification:
- All existing HWQA API endpoints continue to work
- No `cursor(dictionary=True)` calls remain in codebase
- No `ConnectionWrapper` class exists

## What We're NOT Doing

- **NOT** changing the `db_resources` layer itself
- **NOT** switching to use `db.mysql_read()`/`db.mysql_write()` directly (would require larger refactor of the FastAPI service pattern)
- **NOT** changing error handling patterns
- **NOT** changing the reader/writer role-based connection pattern
- **NOT** modifying stored procedure execution patterns

## Implementation Approach

The change is straightforward: replace all `cursor(dictionary=True)` calls with `cursor(pymysql.cursors.DictCursor)` and simplify the `DatabaseConnection` class.

---

## Phase 1: Update DatabaseConnection Class

### Overview
Simplify the `DatabaseConnection` class by removing `ConnectionWrapper` and exposing the raw pymysql connection.

### Changes Required:

#### 1. Simplify connection.py
**File**: `lambdas/lf-vero-prod-hwqa/app/database/connection.py`

**Remove**: The entire `ConnectionWrapper` class (lines 22-61)

**Update**: The `DatabaseConnection` class to return raw pymysql connection:

```python
"""
Database connection layer for hwqa.

This module wraps the assetwatch db_resources layer to provide
DatabaseConnection interface that hwqa routes expect.
"""
import logging
from typing import Optional

import pymysql
import db_resources as db

logger = logging.getLogger(__name__)

# Constants for db_resources
RDS_MAIN_DB = "MAIN_DB_PROXY"
RDS_READ_REPLICA_DB = "MAIN_DB_RR_1"


class DatabaseConnection:
    """
    Database connection wrapper using db_resources.

    Provides role-based connection management (reader/writer) using
    the assetwatch db_resources layer for actual connections.
    """

    def __init__(self, role: str):
        """
        Initialize database connection.

        Args:
            role: Either "reader" or "writer" to determine which database to use
        """
        self.role = role
        self._connection = None
        self._db_option = RDS_READ_REPLICA_DB if role == "reader" else RDS_MAIN_DB

    def connect(self) -> bool:
        """
        Establish database connection using db_resources.

        Returns:
            True if connection successful, False otherwise
        """
        try:
            self._connection = db.get_connection(self._db_option)
            return True
        except Exception as e:
            logger.error(f"Database connection failed: {e}")
            return False

    @property
    def connection(self):
        """
        Get the underlying database connection.

        Returns:
            The pymysql connection object
        """
        return self._connection

    def test_connection(self) -> bool:
        """
        Test connection with a safe query.

        Returns:
            True if connection is valid, False otherwise
        """
        try:
            if not self._connection:
                return False

            cursor = self._connection.cursor()
            cursor.execute("SELECT 1")
            cursor.fetchone()
            cursor.close()
            return True
        except Exception as e:
            logger.error(f"Error testing connection: {e}")
            return False

    def execute_procedure(self, procedure_name: str, params: tuple = ()) -> Optional[list]:
        """
        Execute a stored procedure and return results.

        Args:
            procedure_name: Name of the stored procedure
            params: Parameters to pass to the procedure

        Returns:
            List of result dictionaries or None on error
        """
        try:
            if not self._connection:
                raise Exception("Not connected to database")

            cursor = self._connection.cursor(pymysql.cursors.DictCursor)
            cursor.callproc(procedure_name, params)

            results = cursor.fetchall()

            if self.role == "writer":
                self._connection.commit()

            cursor.close()
            return results

        except Exception as e:
            logger.error(f"Error executing procedure {procedure_name}: {e}")
            raise

    def close(self):
        """Close the database connection."""
        if self._connection:
            try:
                self._connection.close()
                logger.debug("Database connection closed")
            except Exception as e:
                logger.error(f"Error closing connection: {e}")
            finally:
                self._connection = None
```

### Success Criteria:

#### Automated Verification:
- [x] Lambda deploys successfully
- [x] No syntax errors in connection.py

#### Manual Verification:
- [ ] `/health` endpoint returns healthy status
- [ ] `/connection-info` endpoint shows both reader and writer connected

---

## Phase 2: Update All Route Files

### Overview
Replace all `cursor(dictionary=True)` calls with `cursor(pymysql.cursors.DictCursor)` and add pymysql import.

### Changes Required:

For each file, add the pymysql import and replace cursor calls:

```python
# Add import at top of file
import pymysql

# Replace all occurrences of:
cursor = db.connection.cursor(dictionary=True)

# With:
cursor = db.connection.cursor(pymysql.cursors.DictCursor)
```

#### Files to Update (12 files):

1. **app/middleware.py**
   - Add `import pymysql`
   - Replace cursor calls

2. **app/routes/auth_routes.py**
   - No cursor calls using dictionary=True, only uses DatabaseConnection

3. **app/routes/bulk_test_routes.py**
   - Add `import pymysql`
   - Replace cursor calls (6 occurrences)

4. **app/routes/glossary_routes.py**
   - Add `import pymysql`
   - Replace cursor calls (5 occurrences)

5. **app/routes/hub_dashboard_routes.py**
   - Add `import pymysql`
   - Replace cursor calls (1 occurrence)

6. **app/routes/hub_shipment_routes.py**
   - Add `import pymysql`
   - Replace cursor calls (2 occurrences)

7. **app/routes/hub_test_routes.py**
   - Add `import pymysql`
   - Replace cursor calls (6 occurrences)

8. **app/routes/sensor_conversion_routes.py**
   - Add `import pymysql`
   - Replace cursor calls (8 occurrences)

9. **app/routes/sensor_dashboard_routes.py**
   - Add `import pymysql`
   - Replace cursor calls (1 occurrence)

10. **app/routes/sensor_shipment_routes.py**
    - Add `import pymysql`
    - Replace cursor calls (2 occurrences)

11. **app/routes/sensor_test_routes.py**
    - Add `import pymysql`
    - Replace cursor calls (6 occurrences)

12. **app/routes/shared_dashboard_routes.py**
    - Add `import pymysql`
    - Replace cursor calls (1 occurrence)

### Success Criteria:

#### Automated Verification:
- [x] No `cursor(dictionary=True)` calls remain: `grep -r "dictionary=True" lambdas/lf-vero-prod-hwqa/`
- [x] Lambda deploys successfully
- [x] All route files have pymysql import

#### Manual Verification:
- [ ] Test a read endpoint (e.g., GET /sensor/tests)
- [ ] Test a write endpoint (e.g., POST /sensor/tests)
- [ ] Test bulk operations
- [ ] Test stored procedure calls (sensor conversion)

---

## Phase 3: Verify and Cleanup

### Overview
Final verification that all changes work correctly and no remnants of the old pattern remain.

### Verification Steps:

1. **Search for any remaining mysql.connector references:**
   ```bash
   grep -r "mysql.connector\|mysql_connector\|dictionary=True" lambdas/lf-vero-prod-hwqa/
   ```

2. **Verify ConnectionWrapper is removed:**
   ```bash
   grep -r "ConnectionWrapper" lambdas/lf-vero-prod-hwqa/
   ```

3. **Test all major endpoints:**
   - Sensor tests CRUD
   - Hub tests CRUD
   - Bulk operations
   - Dashboard queries
   - Glossary management
   - Sensor conversions

### Success Criteria:

#### Automated Verification:
- [x] No mysql.connector references in codebase
- [x] No ConnectionWrapper references in codebase
- [ ] All endpoints respond without errors

#### Manual Verification:
- [ ] Full regression test of HWQA functionality
- [ ] Performance acceptable (no slowdown from changes)

---

## Testing Strategy

### Unit Tests:
- No unit tests exist for HWQA currently, so this is not applicable

### Integration Tests:
- All endpoints should be tested via manual API calls
- Focus on:
  - Read operations (dashboard, test retrieval)
  - Write operations (logging tests)
  - Stored procedures (sensor conversion)
  - Bulk operations

### Manual Testing Steps:
1. Open HWQA in browser
2. Navigate to sensor tests page - verify data loads
3. Log a new test result - verify it saves
4. Navigate to hub tests page - verify data loads
5. Test bulk serial number loading
6. Test sensor conversion functionality
7. Test glossary CRUD operations

## Performance Considerations

None - this change has no performance impact. We're simply removing a thin wrapper class that was translating one cursor syntax to another. The underlying pymysql driver and db_resources layer remain unchanged.

## Migration Notes

No migration needed - this is purely a code refactor with no data or infrastructure changes.

## References

- `lambdas/lf-vero-prod-hwqa/app/database/connection.py` - Current ConnectionWrapper implementation
- `lambdas/layers/db_resources_311/python/db_resources.py` - db_resources layer used by HWQA
- Assetwatch pymysql patterns in other lambdas (e.g., `lf-vero-prod-hub`, `lf-vero-prod-opportunities`)
