#!/usr/bin/env bats
source $BATS_TEST_DIRNAME/../artifacts/opt/jboss/container/wildfly/s2i/galleon/s2i_galleon

@test "No channel defined" {
  run galleon_parse_channels
  [ "${output}" = "" ]
  [ "$status" -eq 0 ]
}

@test "Channel Manifests coordinates and URLS" {
  expected="<channels><channel><manifest><groupId>org.foo</groupId><artifactId>bar</artifactId><version>1.0</version></manifest></channel>\
<channel><manifest><groupId>com.foo</groupId><artifactId>bar2</artifactId></manifest></channel><channel><manifest><url>file:///tmp/manifest.yaml</url></manifest></channel>\
<channel><manifest><url>http://example.com/channel2.yaml</url></manifest></channel></channels>"
  GALLEON_PROVISION_CHANNELS="org.foo:bar:1.0,com.foo:bar2,file:///tmp/manifest.yaml,http://example.com/channel2.yaml"
  run galleon_parse_channels
  echo "${output}"
  echo "${expected}"
  [ "${output}" = "${expected}" ]
  [ "$status" -eq 0 ]
}