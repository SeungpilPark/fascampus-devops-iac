```shell
cd test
go mod init "<MODULE_NAME>"
go mod tidy
```

```shell
go test -v -timeout 15m -run 'TestHelloWorldAppUnit'
```
