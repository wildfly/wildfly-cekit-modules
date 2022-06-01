#!/usr/bin/env bats
source $BATS_TEST_DIRNAME/../artifacts/opt/jboss/container/wildfly/s2i/galleon/s2i_galleon

@test "No channel defined" {
  run galleon_parse_channels
  [ "${output}" = "" ]
  [ "$status" -eq 0 ]
}

@test "Channel coordinates and URLS" {
  expected="<channels><channel><groupId>org.foo</groupId><artifactId>bar</artifactId><version>1.0</version></channel>\
<channel><groupId>com.foo</groupId><artifactId>bar2</artifactId></channel><channel><url>file:///tmp/channel.yaml</url></channel>\
<channel><url>http://example.com/channel2.yaml</url></channel></channels>"
  GALLEON_PROVISION_CHANNELS="org.foo:bar:1.0,com.foo:bar2,file:///tmp/channel.yaml,http://example.com/channel2.yaml"
  run galleon_parse_channels
  echo "${output}"
  echo "${expected}"
  [ "${output}" = "${expected}" ]
  [ "$status" -eq 0 ]
}
