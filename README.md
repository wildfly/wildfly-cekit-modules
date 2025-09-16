TEST
# wildfly-cekit-modules

A set of [CEKit](https://github.com/cekit/cekitmodules) modules used to build [WildFly S2I](https://github.com/wildfly/wildfly-s2i/)
images and [WildFly Cloud Galleon feature-pack](https://github.com/wildfly-extras/wildfly-cloud-galleon-pack).

These CEKit modules cover:

* WildFly s2i implementation.
* WildFly Galleon layers adjustment for the cloud.
* Bash launch scripts executed when WildFly starts in WildFly s2i images.

## Tests executed for new Pull request

* bat tests are executed in all cases.
* If the changes impact the WildFly s2i builder images, a WildFly s2i image is built and WildFly s2i behave tests are run
* If the changes impact the WildFly cloud Galleon feature-pack, a custom cloud feature-pack is built and WildFly s2i behave tests are run with this custom cloud fp.

### Behave tests execution

#### Steps

Behave tests are run when a PR is opened against the wildfly-cekit-modules repository with changes that impact the WildFLy cloud feature-pack or the WildFly s2i image.
The github action workflow files are:

* [WildFly S2i impact workflow file](https://github.com/wildfly/wildfly-cekit-modules/blob/main/.github/workflows/test-wildfly-s2i.yml)
* [WildFly Cloud galleon feature-pack impact workflow file](https://github.com/wildfly/wildfly-cekit-modules/blob/main/.github/workflows/test-wildfly-cloud-fp.yml)

The steps are as follow:

* Build an image to run behave tests against (according to the executed workflow file).
* Then, for each behave feature [files](https://github.com/wildfly/wildfly-s2i/tree/main/wildfly-builder-image/tests/features):
* Execute the test, and redirect logs to `test-logs-<feature file name>.txt`
* call `docker system prune` to release unreferenced images.
* If a failure occurs, the workflow is aborted and the logs are collected.

#### Understanding the failure logs

The features test execution has been split into multiple executions due to created images resource consumption and log size.
Each feature file has its own execution with its own log.
When a failure occurs:
* Check the Github action execution log. Note the feature file name that failed.
* Download the log files.
* Unzip the log files and search for the `wildfly-s2i-test-logs/**/test-logs-<failing file>.txt` file.
* Access the end of the file: `tail -f --lines 100 <path of the file>`
* You should see something like:
```
Failing scenarios:
  features/image/no-jdk11-legacy-s2i.feature:4  Test preview FP and preview cloud FP with legacy app.

1 feature passed, 1 failed, 0 skipped
9 scenarios passed, 1 failed, 0 skipped
38 steps passed, 1 failed, 3 skipped, 0 undefined
Took 8m17.543s
```
You can then grep the feature name inside the file, for example (`Test preview FP and preview cloud FP with legacy app.`) and look at the failure.

NOTE: The S2I build logs contain ERROR traces that are not actual errors, just traces. For example: 

`ERROR I0426 14:07:03.322859  349849 build.go:51] Running S2I version "v1.3.1"`

You can ignore such traces. Search for `Traceback`, that is the stack trace of the failure. 
