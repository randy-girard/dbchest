# MySQL Version Compatibility Guide

This document outlines MySQL version compatibility with different Ubuntu versions in DBChest.

## Supported MySQL Versions

DBChest supports the following MySQL versions:

- **MySQL 5.7** (Legacy LTS)
- **MySQL 8.0** (Current LTS - Default)
- **MySQL 8.1** (Innovation Release)
- **MySQL 8.2** (Innovation Release)
- **MySQL 8.3** (Innovation Release)
- **MySQL 8.4** (Innovation Release - Latest)

## Ubuntu Compatibility Matrix

| MySQL Version | Ubuntu 18.04 | Ubuntu 20.04 | Ubuntu 22.04 | Ubuntu 24.04 |
|---------------|--------------|--------------|--------------|--------------|
| 5.7           | ✅ Default   | ✅ Available | ❌ Not Available | ❌ Not Available |
| 8.0           | ✅ Available | ✅ Default   | ✅ Default   | ✅ Default   |
| 8.1           | ❌ Not Available | ❌ Not Available | ✅ Available | ✅ Available |
| 8.2           | ❌ Not Available | ❌ Not Available | ✅ Available | ✅ Available |
| 8.3           | ❌ Not Available | ❌ Not Available | ✅ Available | ✅ Available |
| 8.4           | ❌ Not Available | ❌ Not Available | ✅ Available | ✅ Available |

## Version-Specific Installation Details

### MySQL 5.7 (Legacy LTS)

**Supported Ubuntu Versions:** 18.04, 20.04

**Installation Method:**
- **Ubuntu 18.04**: Available in default repositories
- **Ubuntu 20.04**: Available in universe repository (requires `add-apt-repository universe`)
- **Ubuntu 22.04+**: Not available - use MySQL 8.0 or later

**Compatibility Notes:**
- MySQL 5.7 reached End of Life in October 2023
- Only use for legacy applications that require MySQL 5.7
- Consider upgrading to MySQL 8.0 for new deployments
- GTID replication is supported but less stable than 8.0+

**Installation Command:**
```bash
# Ubuntu 20.04
add-apt-repository universe -y
apt-get update
apt-get install -y mysql-server-5.7 mysql-client-5.7

# Ubuntu 18.04
apt-get update
apt-get install -y mysql-server mysql-client
```

### MySQL 8.0 (Current LTS - Default)

**Supported Ubuntu Versions:** 18.04, 20.04, 22.04, 24.04

**Installation Method:**
- Available in default repositories for all supported Ubuntu versions
- This is the recommended version for production use

**Compatibility Notes:**
- Long Term Support (LTS) release
- Stable and well-tested
- Full GTID replication support
- Default authentication plugin: `caching_sha2_password`
- Excellent performance and security features

**Installation Command:**
```bash
apt-get update
apt-get install -y mysql-server mysql-client
```

### MySQL 8.1, 8.2, 8.3, 8.4 (Innovation Releases)

**Supported Ubuntu Versions:** 22.04, 24.04

**Installation Method:**
- Requires MySQL APT repository
- Not available in default Ubuntu repositories
- Installed via MySQL APT config package

**Compatibility Notes:**
- Innovation releases have shorter support lifecycles
- Include latest features and improvements
- May have breaking changes between versions
- Recommended for testing new features, not production
- Requires Ubuntu 22.04 or later

**Installation Command:**
```bash
# Download and install MySQL APT config
wget https://dev.mysql.com/get/mysql-apt-config_0.8.29-1_all.deb
dpkg -i mysql-apt-config_0.8.29-1_all.deb
apt-get update
apt-get install -y mysql-server mysql-client
```

## Replication Compatibility

### GTID-Based Replication

All MySQL versions 5.6+ support GTID (Global Transaction ID) based replication:

- **MySQL 5.7**: GTID supported, requires explicit configuration
- **MySQL 8.0+**: GTID fully supported and recommended

### Cross-Version Replication

**Supported Scenarios:**
- ✅ MySQL 5.7 → MySQL 8.0 (upgrade path)
- ✅ MySQL 8.0 → MySQL 8.0 (same version)
- ✅ MySQL 8.x → MySQL 8.x (same major version)

**Not Recommended:**
- ⚠️ MySQL 8.0 → MySQL 5.7 (downgrade - may cause issues)
- ⚠️ MySQL 8.4 → MySQL 8.0 (innovation to LTS - test thoroughly)

## Authentication Plugins

Different MySQL versions use different default authentication plugins:

| MySQL Version | Default Auth Plugin | Notes |
|---------------|---------------------|-------|
| 5.7           | `mysql_native_password` | Legacy, widely compatible |
| 8.0           | `caching_sha2_password` | More secure, may require client updates |
| 8.1+          | `caching_sha2_password` | Same as 8.0 |

## Troubleshooting Common Issues

### MySQL 5.7 Installation Fails on Ubuntu 22.04

**Error:**
```
E: Package 'mysql-server-5.7' has no installation candidate
E: Package 'mysql-client-5.7' has no installation candidate
```

**Solution:**
MySQL 5.7 is not available on Ubuntu 22.04. Use MySQL 8.0 instead:
1. Select MySQL 8.0 when creating the cluster
2. Or upgrade your existing application to support MySQL 8.0

### MySQL 8.1+ Installation Fails on Ubuntu 20.04

**Error:**
```
MySQL 8.x requires Ubuntu 22.04 or later.
```

**Solution:**
Innovation releases require Ubuntu 22.04+. Either:
1. Use Ubuntu 22.04 or later for your nodes
2. Use MySQL 8.0 (LTS) which works on Ubuntu 20.04

### Authentication Plugin Compatibility

**Error:**
```
Authentication plugin 'caching_sha2_password' cannot be loaded
```

**Solution:**
This occurs when connecting from older clients to MySQL 8.0+:
1. Update your MySQL client library to 8.0+
2. Or create users with `mysql_native_password`:
   ```sql
   CREATE USER 'user'@'%' IDENTIFIED WITH mysql_native_password BY 'password';
   ```

## Recommendations

### For Production Use

1. **Use MySQL 8.0 (LTS)** - Most stable and widely supported
2. **Use Ubuntu 22.04** - Best compatibility with all MySQL versions
3. **Enable GTID replication** - Simplifies replica management
4. **Keep same version** across primary and replicas

### For Development/Testing

1. **MySQL 8.4** - Latest features and improvements
2. **Ubuntu 22.04 or 24.04** - Latest OS features
3. **Test thoroughly** before promoting to production

### For Legacy Applications

1. **MySQL 5.7** on **Ubuntu 20.04** - Last supported combination
2. **Plan migration** to MySQL 8.0 - MySQL 5.7 is EOL
3. **Test compatibility** with MySQL 8.0 before migrating

## Version Selection in DBChest

When creating a MySQL cluster in DBChest:

1. **Select Database Type**: Choose "MySQL"
2. **Select Version**: Choose from available versions
3. **Check Compatibility Notes**: Review the compatibility warning if shown
4. **Select Ubuntu Version**: Ensure your provider template uses a compatible Ubuntu version

DBChest will automatically:
- Show compatibility warnings for incompatible combinations
- Use the correct installation commands for your Ubuntu version
- Configure GTID replication for MySQL 5.7+
- Set up proper logging and error reporting

## Further Reading

- [MySQL 8.0 Documentation](https://dev.mysql.com/doc/refman/8.0/en/)
- [MySQL 5.7 Documentation](https://dev.mysql.com/doc/refman/5.7/en/)
- [MySQL Replication](https://dev.mysql.com/doc/refman/8.0/en/replication.html)
- [GTID Replication](https://dev.mysql.com/doc/refman/8.0/en/replication-gtids.html)

