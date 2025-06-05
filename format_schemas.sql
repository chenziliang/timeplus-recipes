-- format schema

CREATE FORMAT SCHEMA foo as '
syntax = "proto3";

message Foo {
  string a = 1;
  int64 b = 2;
}
' TYPE Protobuf;

CREATE EXTERNAL STREAM foo (
    a string,
    b int64
) SETTINGS type='kafka',...,data_format='ProtobufSingle',format_schema='foo:Foo';

SELECT * FROM foo;
