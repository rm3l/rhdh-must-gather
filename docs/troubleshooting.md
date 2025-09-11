## Troubleshooting

### Common Issues

**No RHDH deployment detected**
- Verify RHDH is running in the cluster
- Check if it's in a non-standard namespace
- Ensure proper RBAC permissions

**Command timeouts**
- Increase `CMD_TIMEOUT` environment variable (default: 30 seconds)
- Check cluster network connectivity
- Verify sufficient resources

**Permission denied errors**
- Ensure the tool has cluster-admin or sufficient RBAC permissions
- Check ServiceAccount configuration in OpenShift

### Getting Help

1. Check the tool output files in `/must-gather/rhdh/` for what was detected
2. Review the `must-gather.log` file for container execution logs
3. Check the `sanitization-report.txt` file for data sanitization summary
4. Check individual script outputs:
    - `/must-gather/rhdh/helm/all-rhdh-releases.txt` for Helm deployment detection
    - `/must-gather/rhdh/operator/all-deployments.txt` for Operator deployment detection
5. Verify cluster connectivity with `kubectl cluster-info`
6. Run with debug logging: `LOG_LEVEL=debug` to see detailed execution information
