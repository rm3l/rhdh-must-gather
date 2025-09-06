# Changelog

## 1.0.0 (2025-09-06)


### Features

* Focus on RHDH-specific data and fix operator data collection ([4bb0807](https://github.com/rm3l/rhdh-must-gather/commit/4bb0807f86f49cfb9b14715bd4dbe9ecc14c28c3))
* make resources collection optional by default since it takes time ([b088637](https://github.com/rm3l/rhdh-must-gather/commit/b08863714db0d1de533644fcc96db8423fe2c9a1))
* make sure to honor --since and --since-time args that can be passed to oc must-gather ([a9e95f2](https://github.com/rm3l/rhdh-must-gather/commit/a9e95f2bbf2e2535f117348ea083685466be3ade))


### Bug Fixes

* Fix collection of operator and Helm based instances ([37382e5](https://github.com/rm3l/rhdh-must-gather/commit/37382e566938c022ef94df85231e63e9068c9c89))
* Fix exec command to retrieve files from running pods ([2bd949d](https://github.com/rm3l/rhdh-must-gather/commit/2bd949dc29142e1129f3be57f25183c0dee686f6))
* Fix Helm releases and Backstage CR detection in multiple namespaces ([4324c60](https://github.com/rm3l/rhdh-must-gather/commit/4324c60739fd442752a532ac6070bf74d2c7a936))
* Fix issue with the date commnd when collecting events ([eaefe6c](https://github.com/rm3l/rhdh-must-gather/commit/eaefe6c86de7dd7ca8f7feb55d41f250c966a9c6))
* Fix logs and events collection ([5a69e7c](https://github.com/rm3l/rhdh-must-gather/commit/5a69e7c4256c81daedd659326fbf6d149e699b41))
* Fix RHDH detection in multiple namespaces ([84daa5b](https://github.com/rm3l/rhdh-must-gather/commit/84daa5bfb5fcac80da4f74a46c6bd88e4f3fb0d2))
* Fix sanitization script ([0c0917b](https://github.com/rm3l/rhdh-must-gather/commit/0c0917b44074d176e5cfd17e2b6e421b07012dcc))
* Fix test-local-all target ([7ee77ca](https://github.com/rm3l/rhdh-must-gather/commit/7ee77cabbfb9f1b6bc69a8717cd1db25054a24d5))
* handle the case where the instances and operator live in any namespace ([1bc43ad](https://github.com/rm3l/rhdh-must-gather/commit/1bc43ad855ba9f65dcfd8740b4a87baae9134ced))
