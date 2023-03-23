# wildfly-cekit-module testing

Tests are provided for modules defined in this repository.

Tests are based on the [Bash Automated Testing System](https://github.com/bats-core/bats-core) framework which 
permits defining, executing and reporting on tests implemented as generized bash scripts.

The tests can be used to start a container image with a set of pre-defined parameters, load the module to be tested 
and then test assertions on the effect of the module on the container image. By convention, tests are included in the _tests_ sub-directory of the directory containing the module definition file.

These tests are aimed at validating the configurational integrity of the module; in other words,
to validate that the effect of adding the module to the image definition file is
as expected. These assertions include, but are not limited to, checking that image configuration files have been
correctly updated for execution the cloud. 







