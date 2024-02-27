# ch09. opa-terraform

Terraform을 사용하면 원하는 인프라를 설명하고 그에 맞게 기존 인프라를 자동으로 생성, 삭제 및 수정할 수 있습니다. OPA를 사용하면 Terraform이 변경하려는 사항을 변경하기 전에 테스트하는 정책을 작성할 수 있습니다. 이러한 테스트는 다양한 방식으로 도움이 됩니다:

*   테스트를 통해 개별 개발자가 테라폼 변경 사항을 점검할 수 있습니다.
    
*   테스트는 일상적인 인프라 변경 사항을 자동으로 승인하고 동료 검토의 부담을 줄여줍니다.
    
*   테스트는 스테이징에 적용한 후 프로덕션에 적용할 때 발생하는 문제를 파악하는 데 도움이 됩니다.
    

Terraform 사용 사례를 지원하는 OPA 에코시스템에 나열된 [7개의 프로젝트를](https://www.openpolicyagent.org/ecosystem/terraform) 중, Terraform Cloud 연동도 있습니다.

## 목표

이 튜토리얼에서는 OPA를 사용하여 자동 확장 그룹 및 서버를 생성하고 삭제하는 Terraform 계획에 대한 단위 테스트를 구현하는 방법을 알아봅니다.

## 전제 조건

이 튜토리얼에는 다음이 필요합니다.

*   [Terraform 0.12.6](https://releases.hashicorp.com/terraform/0.12.6/)
    
*   [OPA](https://github.com/open-policy-agent/opa/releases)
    

# 시작하기

## Steps

### 1\. Terraform plan 생성 및 저장

AWS에서 자동 확장 그룹과 서버를 포함하는 [Terraform](https://www.terraform.io/docs/) 파일을 만듭니다. (AWS 자격 증명을 가리키도록 `shared_credentials_file을`수정해야 합니다.)

```
cat >main.tf <<EOF
provider "aws" {
    region = "us-west-1"
}
resource "aws\_instance" "web" {
  instance\_type = "t2.micro"
  ami = "ami-09b4b74c"
}
resource "aws\_autoscaling\_group" "my\_asg" {
  availability\_zones        = \["us-west-1a"\]
  name                      = "my\_asg"
  max\_size                  = 5
  min\_size                  = 1
  health\_check\_grace\_period = 300
  health\_check\_type         = "ELB"
  desired\_capacity          = 4
  force\_delete              = true
  launch\_configuration      = "my\_web\_config"
}
resource "aws\_launch\_configuration" "my\_web\_config" {
    name = "my\_web\_config"
    image\_id = "ami-09b4b74c"
    instance\_type = "t2.micro"
}
EOF

```

그런 다음 Terraform을 초기화하고 어떤 변경 사항을 계산하고 그 결과를 `plan.binary에` 저장하도록 요청합니다.

```
terraform init
terraform plan --out tfplan.binary

```

### 2\. 테라폼 plan 을 JSON으로 변환

[terraform show](https://www.terraform.io/docs/commands/show.html) 명령을 사용하여 테라폼 계획을 JSON으로 변환하여 OPA가 계획을 읽을 수 있도록 합니다.

```
terraform show -json tfplan.binary > tfplan.json

```

다음은 `tfplan.json의` 예상 내용입니다.

```
{
  "format\_version": "0.1",
  "terraform\_version": "0.12.6",
  "planned\_values": {
    "root\_module": {
      "resources": \[
        {
          "address": "aws\_autoscaling\_group.my\_asg",
          "mode": "managed",
          "type": "aws\_autoscaling\_group",
          "name": "my\_asg",
          "provider\_name": "aws",
          "schema\_version": 0,
          "values": {
            "availability\_zones": \[
              "us-west-1a"
            \],
            "desired\_capacity": 4,
            "enabled\_metrics": null,
            "force\_delete": true,
            "health\_check\_grace\_period": 300,
            "health\_check\_type": "ELB",
            "initial\_lifecycle\_hook": \[\],
            "launch\_configuration": "my\_web\_config",
            "launch\_template": \[\],
            "max\_size": 5,
            "metrics\_granularity": "1Minute",
            "min\_elb\_capacity": null,
            "min\_size": 1,
            "mixed\_instances\_policy": \[\],
            "name": "my\_asg",
            "name\_prefix": null,
            "placement\_group": null,
            "protect\_from\_scale\_in": false,
            "suspended\_processes": null,
            "tag": \[\],
            "tags": null,
            "termination\_policies": null,
            "timeouts": null,
            "wait\_for\_capacity\_timeout": "10m",
            "wait\_for\_elb\_capacity": null
          }
        },
        {
          "address": "aws\_instance.web",
          "mode": "managed",
          "type": "aws\_instance",
          "name": "web",
          "provider\_name": "aws",
          "schema\_version": 1,
          "values": {
            "ami": "ami-09b4b74c",
            "credit\_specification": \[\],
            "disable\_api\_termination": null,
            "ebs\_optimized": null,
            "get\_password\_data": false,
            "iam\_instance\_profile": null,
            "instance\_initiated\_shutdown\_behavior": null,
            "instance\_type": "t2.micro",
            "monitoring": null,
            "source\_dest\_check": true,
            "tags": null,
            "timeouts": null,
            "user\_data": null,
            "user\_data\_base64": null
          }
        },
        {
          "address": "aws\_launch\_configuration.my\_web\_config",
          "mode": "managed",
          "type": "aws\_launch\_configuration",
          "name": "my\_web\_config",
          "provider\_name": "aws",
          "schema\_version": 0,
          "values": {
            "associate\_public\_ip\_address": false,
            "enable\_monitoring": true,
            "ephemeral\_block\_device": \[\],
            "iam\_instance\_profile": null,
            "image\_id": "ami-09b4b74c",
            "instance\_type": "t2.micro",
            "name": "my\_web\_config",
            "name\_prefix": null,
            "placement\_tenancy": null,
            "security\_groups": null,
            "spot\_price": null,
            "user\_data": null,
            "user\_data\_base64": null,
            "vpc\_classic\_link\_id": null,
            "vpc\_classic\_link\_security\_groups": null
          }
        }
      \]
    }
  },
  "resource\_changes": \[
    {
      "address": "aws\_autoscaling\_group.my\_asg",
      "mode": "managed",
      "type": "aws\_autoscaling\_group",
      "name": "my\_asg",
      "provider\_name": "aws",
      "change": {
        "actions": \[
          "create"
        \],
        "before": null,
        "after": {
          "availability\_zones": \[
            "us-west-1a"
          \],
          "desired\_capacity": 4,
          "enabled\_metrics": null,
          "force\_delete": true,
          "health\_check\_grace\_period": 300,
          "health\_check\_type": "ELB",
          "initial\_lifecycle\_hook": \[\],
          "launch\_configuration": "my\_web\_config",
          "launch\_template": \[\],
          "max\_size": 5,
          "metrics\_granularity": "1Minute",
          "min\_elb\_capacity": null,
          "min\_size": 1,
          "mixed\_instances\_policy": \[\],
          "name": "my\_asg",
          "name\_prefix": null,
          "placement\_group": null,
          "protect\_from\_scale\_in": false,
          "suspended\_processes": null,
          "tag": \[\],
          "tags": null,
          "termination\_policies": null,
          "timeouts": null,
          "wait\_for\_capacity\_timeout": "10m",
          "wait\_for\_elb\_capacity": null
        },
        "after\_unknown": {
          "arn": true,
          "availability\_zones": \[
            false
          \],
          "default\_cooldown": true,
          "id": true,
          "initial\_lifecycle\_hook": \[\],
          "launch\_template": \[\],
          "load\_balancers": true,
          "mixed\_instances\_policy": \[\],
          "service\_linked\_role\_arn": true,
          "tag": \[\],
          "target\_group\_arns": true,
          "vpc\_zone\_identifier": true
        }
      }
    },
    {
      "address": "aws\_instance.web",
      "mode": "managed",
      "type": "aws\_instance",
      "name": "web",
      "provider\_name": "aws",
      "change": {
        "actions": \[
          "create"
        \],
        "before": null,
        "after": {
          "ami": "ami-09b4b74c",
          "credit\_specification": \[\],
          "disable\_api\_termination": null,
          "ebs\_optimized": null,
          "get\_password\_data": false,
          "iam\_instance\_profile": null,
          "instance\_initiated\_shutdown\_behavior": null,
          "instance\_type": "t2.micro",
          "monitoring": null,
          "source\_dest\_check": true,
          "tags": null,
          "timeouts": null,
          "user\_data": null,
          "user\_data\_base64": null
        },
        "after\_unknown": {
          "arn": true,
          "associate\_public\_ip\_address": true,
          "availability\_zone": true,
          "cpu\_core\_count": true,
          "cpu\_threads\_per\_core": true,
          "credit\_specification": \[\],
          "ebs\_block\_device": true,
          "ephemeral\_block\_device": true,
          "host\_id": true,
          "id": true,
          "instance\_state": true,
          "ipv6\_address\_count": true,
          "ipv6\_addresses": true,
          "key\_name": true,
          "network\_interface": true,
          "network\_interface\_id": true,
          "password\_data": true,
          "placement\_group": true,
          "primary\_network\_interface\_id": true,
          "private\_dns": true,
          "private\_ip": true,
          "public\_dns": true,
          "public\_ip": true,
          "root\_block\_device": true,
          "security\_groups": true,
          "subnet\_id": true,
          "tenancy": true,
          "volume\_tags": true,
          "vpc\_security\_group\_ids": true
        }
      }
    },
    {
      "address": "aws\_launch\_configuration.my\_web\_config",
      "mode": "managed",
      "type": "aws\_launch\_configuration",
      "name": "my\_web\_config",
      "provider\_name": "aws",
      "change": {
        "actions": \[
          "create"
        \],
        "before": null,
        "after": {
          "associate\_public\_ip\_address": false,
          "enable\_monitoring": true,
          "ephemeral\_block\_device": \[\],
          "iam\_instance\_profile": null,
          "image\_id": "ami-09b4b74c",
          "instance\_type": "t2.micro",
          "name": "my\_web\_config",
          "name\_prefix": null,
          "placement\_tenancy": null,
          "security\_groups": null,
          "spot\_price": null,
          "user\_data": null,
          "user\_data\_base64": null,
          "vpc\_classic\_link\_id": null,
          "vpc\_classic\_link\_security\_groups": null
        },
        "after\_unknown": {
          "ebs\_block\_device": true,
          "ebs\_optimized": true,
          "ephemeral\_block\_device": \[\],
          "id": true,
          "key\_name": true,
          "root\_block\_device": true
        }
      }
    }
  \],
  "configuration": {
    "provider\_config": {
      "aws": {
        "name": "aws",
        "expressions": {
          "region": {
            "constant\_value": "us-west-1"
          }
        }
      }
    },
    "root\_module": {
      "resources": \[
        {
          "address": "aws\_autoscaling\_group.my\_asg",
          "mode": "managed",
          "type": "aws\_autoscaling\_group",
          "name": "my\_asg",
          "provider\_config\_key": "aws",
          "expressions": {
            "availability\_zones": {
              "constant\_value": \[
                "us-west-1a"
              \]
            },
            "desired\_capacity": {
              "constant\_value": 4
            },
            "force\_delete": {
              "constant\_value": true
            },
            "health\_check\_grace\_period": {
              "constant\_value": 300
            },
            "health\_check\_type": {
              "constant\_value": "ELB"
            },
            "launch\_configuration": {
              "constant\_value": "my\_web\_config"
            },
            "max\_size": {
              "constant\_value": 5
            },
            "min\_size": {
              "constant\_value": 1
            },
            "name": {
              "constant\_value": "my\_asg"
            }
          },
          "schema\_version": 0
        },
        {
          "address": "aws\_instance.web",
          "mode": "managed",
          "type": "aws\_instance",
          "name": "web",
          "provider\_config\_key": "aws",
          "expressions": {
            "ami": {
              "constant\_value": "ami-09b4b74c"
            },
            "instance\_type": {
              "constant\_value": "t2.micro"
            }
          },
          "schema\_version": 1
        },
        {
          "address": "aws\_launch\_configuration.my\_web\_config",
          "mode": "managed",
          "type": "aws\_launch\_configuration",
          "name": "my\_web\_config",
          "provider\_config\_key": "aws",
          "expressions": {
            "image\_id": {
              "constant\_value": "ami-09b4b74c"
            },
            "instance\_type": {
              "constant\_value": "t2.micro"
            },
            "name": {
              "constant\_value": "my\_web\_config"
            }
          },
          "schema\_version": 0
        }
      \]
    }
  }
}
```

테라폼에서 생성된 json 계획 출력에는 많은 정보가 포함되어 있습니다. 이 튜토리얼에서는 다음과 같은 정보에 관심을 갖겠습니다.

*   `.resource_changes: 테라폼이 인프라에 적용할 모든 작업이 포함된 배열입니다.`
    
*   `.resource_changes[].type: 리소스 유형(예: aws_instance, aws_iam...)`
    
*   `.resource_changes[].change.actions`: 리소스에 적용된 작업의 배열 (`create`, `update`, `delete`…)
    

json 계획 표현에 대한 자세한 내용은 [테라폼 문서를](https://www.terraform.io/docs/internals/json-format.html#plan-representation) 참조하세요.

### 3\. OPA 정책을 작성하여 plan 을 확인합니다.

이 정책은 다음을 결합한 테라폼에 대한 점수를 계산합니다.

*   각 리소스 유형의 삭제 횟수
    
*   각 리소스 유형의 생성 개수
    
*   각 리소스 유형의 수정 횟수
    

이 정책은 플랜의 점수가 임계값 미만이고 IAM 리소스에 변경이 없는 경우 플랜을 승인합니다. (간단하게 하기 위해 이 자습서에서 임계값은 모든 사용자에게 동일하지만 실제로는 사용자에 따라 임계값이 달라질 수 있습니다.)

**policy/terraform.rego**:

```
package terraform.analysis

import rego.v1

import input as tfplan

########################
# Parameters for Policy
########################

# acceptable score for automated authorization
blast\_radius := 30

# weights assigned for each operation on each resource-type
weights := {
	"aws\_autoscaling\_group": {"delete": 100, "create": 10, "modify": 1},
	"aws\_instance": {"delete": 10, "create": 1, "modify": 1},
}

# Consider exactly these resource types in calculations
resource\_types := {"aws\_autoscaling\_group", "aws\_instance", "aws\_iam", "aws\_launch\_configuration"}

#########
# Policy
#########

# Authorization holds if score for the plan is acceptable and no changes are made to IAM
default authz := false

authz if {
	score < blast\_radius
	not touches\_iam
}

# Compute the score for a Terraform plan as the weighted sum of deletions, creations, modifications
score := s if {
	all := \[x |
		some resource\_type
		crud := weights\[resource\_type\]
		del := crud\["delete"\] \* num\_deletes\[resource\_type\]
		new := crud\["create"\] \* num\_creates\[resource\_type\]
		mod := crud\["modify"\] \* num\_modifies\[resource\_type\]
		x := (del + new) + mod
	\]
	s := sum(all)
}

# Whether there is any change to IAM
touches\_iam if {
	all := resources.aws\_iam
	count(all) > 0
}

####################
# Terraform Library
####################

# list of all resources of a given type
resources\[resource\_type\] := all if {
	some resource\_type
	resource\_types\[resource\_type\]
	all := \[name |
		name := tfplan.resource\_changes\[\_\]
		name.type == resource\_type
	\]
}

# number of creations of resources of a given type
num\_creates\[resource\_type\] := num if {
	some resource\_type
	resource\_types\[resource\_type\]
	all := resources\[resource\_type\]
	creates := \[res | res := all\[\_\]; res.change.actions\[\_\] == "create"\]
	num := count(creates)
}

# number of deletions of resources of a given type
num\_deletes\[resource\_type\] := num if {
	some resource\_type
	resource\_types\[resource\_type\]
	all := resources\[resource\_type\]
	deletions := \[res | res := all\[\_\]; res.change.actions\[\_\] == "delete"\]
	num := count(deletions)
}

# number of modifications to resources of a given type
num\_modifies\[resource\_type\] := num if {
	some resource\_type
	resource\_types\[resource\_type\]
	all := resources\[resource\_type\]
	modifies := \[res | res := all\[\_\]; res.change.actions\[\_\] == "update"\]
	num := count(modifies)
}
```

### 4\. 테라폼 계획에 대한 OPA 정책 평가하기

해당 계획에 대해 정책을 평가하려면 OPA에 정책과 Terraform 계획을 입력으로 전달하고 `terraform/analysis/authz` 를 평가하도록 요청합니다.

```
opa exec --decision terraform/analysis/authz --bundle policy/ tfplan.json

```

```
true
```

궁금한 점이 있으면 정책이 권한 부여 결정을 내리는 데 사용한 점수를 요청할 수 있습니다. 이 예에서는 11점(자동 확장 그룹 생성에 10점, 서버 생성에 1점)입니다.

```
opa exec --decision terraform/analysis/score --bundle policy/ tfplan.json

```

```
11
```

### 5\. 대규모 테라폼 계획 만들기 및 평가하기

정책에서 허용 초과하는 충분한 리소스를 생성하는 테라폼 계획을 만듭니다.

```
cat >main.tf <<EOF
provider "aws" {
    region = "us-west-1"
}
resource "aws\_instance" "web" {
  instance\_type = "t2.micro"
  ami = "ami-09b4b74c"
}
resource "aws\_autoscaling\_group" "my\_asg" {
  availability\_zones        = \["us-west-1a"\]
  name                      = "my\_asg"
  max\_size                  = 5
  min\_size                  = 1
  health\_check\_grace\_period = 300
  health\_check\_type         = "ELB"
  desired\_capacity          = 4
  force\_delete              = true
  launch\_configuration      = "my\_web\_config"
}
resource "aws\_launch\_configuration" "my\_web\_config" {
    name = "my\_web\_config"
    image\_id = "ami-09b4b74c"
    instance\_type = "t2.micro"
}
resource "aws\_autoscaling\_group" "my\_asg2" {
  availability\_zones        = \["us-west-2a"\]
  name                      = "my\_asg2"
  max\_size                  = 6
  min\_size                  = 1
  health\_check\_grace\_period = 300
  health\_check\_type         = "ELB"
  desired\_capacity          = 4
  force\_delete              = true
  launch\_configuration      = "my\_web\_config"
}
resource "aws\_autoscaling\_group" "my\_asg3" {
  availability\_zones        = \["us-west-2b"\]
  name                      = "my\_asg3"
  max\_size                  = 7
  min\_size                  = 1
  health\_check\_grace\_period = 300
  health\_check\_type         = "ELB"
  desired\_capacity          = 4
  force\_delete              = true
  launch\_configuration      = "my\_web\_config"
}
EOF

```

테라폼 계획을 생성하고 JSON으로 변환합니다.

```
terraform init
terraform plan --out tfplan\_large.binary
terraform show -json tfplan\_large.binary > tfplan\_large.json

```

정책을 평가하여 정책 테스트에 실패했는지 확인하고 점수를 확인합니다.

```
opa exec --decision terraform/analysis/authz --bundle policy/ tfplan\_large.json
opa exec --decision terraform/analysis/score --bundle policy/ tfplan\_large.json

```

### 6\. (선택 사항) 원격 정책 번들을 사용하여 OPA 실행하기

로컬 파일 시스템에서 정책을 로드하는 것 외에도 `opa exec` 는 [Bundles](https://www.openpolicyagent.org/docs/latest/management-bundles) 통해 원격 위치에서 정책을 가져올 수 있습니다. 실제로 작동하는 모습을 보려면 먼저 정책을 번들로 빌드하세요:

```
opa build policy/

```

다음으로 nginx를 통해 번들을 제공합니다:

```
docker run --rm --name bundle\_server -d -p 8888:80 \\
-v ${PWD}:/usr/share/nginx/html:ro nginx:latest

```

그런 다음 번들을 활성화한 상태에서 `opa exec` 실행합니다:

```
opa exec --decision terraform/analysis/authz \\
  --set services.bundle\_server.url=http://localhost:8888 \\
  --set bundles.tutorial.resource=bundle.tar.gz \\
  tfplan\_large.json

```

## Wrap Up

OPA를 사용한 테라폼 테스트에 대해 여러 가지를 배웠습니다:

*   OPA는 Terraform 요금제에 대한 세분화된 정책 제어 기능을 제공합니다.
    
*   권한 부여 정책을 작성할 때 요금제 자체 이외의 데이터(예: 사용자)를 사용할 수 있습니다.
    

OPA의 테라폼 테스트 및 승인 결정에 대한 몇 가지 아이디어입니다.

*   테라폼 래퍼의 일부로 추가하여 테라폼 플랜에서 단위 테스트를 구현하세요.
    
*   이 기능을 사용하여 일상적인 테라폼 변경 사항을 자동으로 승인하여 동료 검토의 부담을 줄이세요.
    
*   배포 시스템에 포함시켜 스테이징에 적용한 후 Terraform을 프로덕션에 적용할 때 발생하는 문제를 파악하세요.
    

테라폼 모듈을 사용하는 추가 예시를 살펴보려면 아래에서 계속 진행하세요.

# 모듈로 작업하기

## 모듈 단계

### 1\. 테라폼 모듈 계획 생성 및 저장

모듈에서 보안 그룹과 보안 그룹이 포함된 새 Terraform 파일을 만듭니다. (이 예에서는 [https://github.com/terraform-aws-modules/terraform-aws-security-group](https://github.com/terraform-aws-modules/terraform-aws-security-group) 의 모듈을 사용합니다.)

```
cat >main.tf <<EOF
provider "aws" {
  region = "us-east-1"
}

data "aws\_vpc" "default" {
  default = true
}

module "http\_sg" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=v3.10.0"

  name        = "http-sg"
  description = "Security group with HTTP ports open for everybody (IPv4 CIDR), egress ports are all world open"
  vpc\_id      = data.aws\_vpc.default.id

  ingress\_cidr\_blocks = \["0.0.0.0/0"\]
}


resource "aws\_security\_group" "allow\_tls" {
  name        = "allow\_tls"
  description = "Allow TLS inbound traffic"
  vpc\_id      = data.aws\_vpc.default.id

  ingress {
    description = "TLS from VPC"
    from\_port   = 443
    to\_port     = 443
    protocol    = "tcp"
    cidr\_blocks = \["10.0.0.0/8"\]
  }

  egress {
    from\_port   = 0
    to\_port     = 0
    protocol    = "-1"
    cidr\_blocks = \["0.0.0.0/0"\]
  }

  tags = {
    Name = "allow\_tls"
  }
}
EOF

```

```
terraform init
terraform plan --out tfplan.binary

```

### 2\. Terraform plan 을 JSON 변경

```
terraform show -json tfplan.binary > tfplan2.json

```

### 3\. Write the OPA policy to collect resources

정책은 보안 그룹의 설명 내용을 기반으로 보안 그룹이 유효한지 평가합니다:

*   리소스는 루트 모듈 또는 하위 모듈에서 지정할 수 있습니다.
    
*   다음 리소스를 결합한 그룹과 비교하여 평가하려고 합니다.
    
*   이 예제는 json 표현의 계획된 변경 섹션으로 범위가 지정됩니다.
    

이 정책은 walk 키워드를 사용하여 json 구조를 탐색하고 조건을 사용하여 리소스를 찾을 수 있는 특정 경로를 필터링합니다.

**policy/terraform\_module.rego**:

```
package terraform.module

import rego.v1

deny contains msg if {
	desc := resources\[r\].values.description
	contains(desc, "HTTP")
	msg := sprintf("No security groups should be using HTTP. Resource in violation: %v", \[r.address\])
}

resources := {r |
	some path, value

	# Walk over the JSON tree and check if the node we are
	# currently on is a module (either root or child) resources
	# value.
	walk(input.planned\_values, \[path, value\])

	# Look for resources in the current value based on path
	rs := module\_resources(path, value)

	# Aggregate them into \`resources\`
	r := rs\[\_\]
}

# Variant to match root\_module resources
module\_resources(path, value) := rs if {
	# Expect something like:
	#
	#     {
	#     	"root\_module": {
	#         	"resources": \[...\],
	#             ...
	#         }
	#         ...
	#     }
	#
	# Where the path is \[..., "root\_module", "resources"\]

	reverse\_index(path, 1) == "resources"
	reverse\_index(path, 2) == "root\_module"
	rs := value
}

# Variant to match child\_modules resources
module\_resources(path, value) := rs if {
	# Expect something like:
	#
	#     {
	#     	...
	#         "child\_modules": \[
	#         	{
	#             	"resources": \[...\],
	#                 ...
	#             },
	#             ...
	#         \]
	#         ...
	#     }
	#
	# Where the path is \[..., "child\_modules", 0, "resources"\]
	# Note that there will always be an index int between \`child\_modules\`
	# and \`resources\`. We know that walk will only visit each one once,
	# so we shouldn't need to keep track of what the index is.

	reverse\_index(path, 1) == "resources"
	reverse\_index(path, 3) == "child\_modules"
	rs := value
}

reverse\_index(path, idx) := value if {
	value := path\[count(path) - idx\]
}

```

### 4\. Terraform 모듈 계획에서 OPA 정책 평가하기

해당 계획에 대해 정책을 평가하려면 OPA에 정책과 Terraform 계획을 입력으로 전달하고 `data.terraform.module.deny를` 평가하도록 요청합니다.

```
opa exec --decision terraform/module/deny --bundle policy/ tfplan2.json

```

```
{
  "result": \[
    {
      "path": "tfplan2.json",
      "result": \[
        "No security groups should be using HTTP. Resource in violation: module.http\_sg.aws\_security\_group.this\_name\_prefix\[0\]"
      \]
    }
  \]
}

```