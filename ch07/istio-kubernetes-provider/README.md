# Managing Kubernetes resources in Terraform: Kubernetes provider

이 예제는 Kubernetes 1.26과 Terraform 1.5를 사용하여 작성되었습니다.

# 시작하기

Terraform용 Kubernetes 공급자는 대부분의 Kubernetes API에 대한 리소스와 데이터 소스를 제공합니다. 예를 들어, Kubernetes Deployment 에 해당하는 Terraform은 kubernetes_deployment 리소스입니다. 이들 모두는 API별로 그룹화된 공급자 문서에서 볼 수 있습니다.

기본 쿠버네티스 API의 일부가 아닌 리소스의 경우, 모든 쿠버네티스 YAML 매니페스트의 HCL 표현이 될 수 있는 kubernetes_manifest 리소스를 사용해야 합니다.

다음 예제는 동일한 Kubernetes 배포를 YAML, Terraform kubernetes_deploy 및 Terraform kubernetes_manifest로 보여주는 예제입니다:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
```

테라폼 HCL에서는 Kubernetes 공급자 kubernetes_deployment 리소스를 사용하여 동일한 배포를 수행합니다:

```terraform
resource "kubernetes_deployment" "nginx" {
  metadata {
    name      = "nginx"
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "nginx"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }

      spec {
        container {
          image = "nginx:1.25.2-alpine"
          name  = "nginx"

          port {
            container_port = 80
          }
        }
      }
    }
  }
}
```

또는 모든 Kubernetes YAML 매니페스트의 HCL 표현이 될 수 있는 kubernetes_manifest 리소스를 사용할 수도 있습니다:

```terraform
resource "kubernetes_manifest" "deployment_nginx_deployment" {
  manifest = {
    "apiVersion" = "apps/v1"
    "kind" = "Deployment"
    "metadata" = {
      "labels" = {
        "app" = "nginx"
      }
      "name" = "nginx"
    }
    "spec" = {
      "replicas" = 2
      "selector" = {
        "matchLabels" = {
          "app" = "nginx"
        }
      }
      "template" = {
        "metadata" = {
          "labels" = {
            "app" = "nginx"
          }
        }
        "spec" = {
          "containers" = [
            {
              "image" = "nginx:1.25.2-alpine"
              "name" = "nginx"
              "ports" = [
                {
                  "containerPort" = 80
                },
              ]
            },
          ]
        }
      }
    }
  }
}
```

두 HCL 버전 모두 동일한 배포 결과를 가져오지만, kubernetes_deployment를 사용하는 것이 덜 장황하고 Terraform이 값에 대한 기본 유효성 검사(예: 복제본이 정수인지 확인하는 것)를 수행합니다. 그러나 위에서 언급했듯이 사용자 정의 리소스의 경우, kubernetes_manifest를 사용하는 것 외에는 다른 옵션이 없습니다.

단일 배포가 아닌 실제 사례로 Istio를 설치해 보겠습니다. 이스티오 데몬을 배포하려면 사용자 정의 리소스 정의(CRD)와 다양한 리소스(RBAC, ServiceAccounts, ConfigMaps 등)가 필요합니다.

# Istio 설치

대부분의 Kubernetes 리소스는 YAML로 배포되므로, 첫 번째 단계는 항상 Terraform HCL로 변환하는 것입니다. 

기본 프로필에 대한 Istio YAML 매니페스트의 길이는 약 10,000줄이며 47개의 Kubernetes 리소스가 포함되어 있습니다. 수동으로 변환을 수행하면 시간이 너무 오래 걸립니다.

변환을 자동화하기 위해 tfk8s를 사용할 수 있습니다. 다음은 Istio YAML 매니페스트를 생성하고 이를 HCL로 변환하는 명령어입니다:

```shell
$ istioctl manifest generate > istio.yaml
$ tfk8s -f istio.yaml > istio.tf
```

# CRD 모듈

CRD가 있는 애플리케이션을 배포할 때 좋은 방법은 자체 테라폼 모듈에 넣는 것입니다. 

쿠버네티스 공급자를 적용할 때 사용자 정의 리소스와 코어 리소스 간에 차이가 없기 때문에 정의가 아직 설치되지 않은 상태에서 사용자 정의 리소스를 배포하려고 시도하는 경우가 발생할 수 있습니다.

Istio를 설치하려면 istio.tf 파일을 두 개의 파일로 (수동으로) 분할해야 하며, 그 중 하나에 CRD가 포함되어 있어야 합니다. 이 파일들을 자체 Terraform 모듈인 istio와 istio-crds에 넣습니다.

디렉토리 트리는 다음과 같이 표시되어야 합니다:

```shell
.
├── istio
│   └── main.tf
├── istio-crds
│   └── main.tf
├── main.tf
```

루트 main.tf 파일에서 이들 사이에 종속성을 추가하여 CRD가 먼저 설치되도록 할 수 있습니다:

```terraform
module "istio-crds" {
  source = "./istio-crds"
}

module "istio" {
  source = "./istio"

  depends_on = [
    module.istio-crds
  ]
}
```

또한 네임스페이스가 자동으로 생성되지 않으므로 main/istio.tf 파일에 네임스페이스를 추가해야 합니다:

```terraform
resource "kubernetes_namespace" "istio_system" {
  metadata {
    name = "istio-system"
  }
}
```

이 시점에서 테라폼 적용을 실행하면 성공하지 못하고 많은 오류가 표시됩니다. 

출력이 너무 길어 이 게시물에는 포함하지 않았지만 다음 두 가지 주요 문제로 그룹화할 수 있습니다.

## 일관성 없는 결과 오류

```shell
Error: Provider produced inconsistent result after apply

When applying changes to kubernetes_manifest.deployment_istio_system_istiod, provider
"provider[\"registry.terraform.io/hashicorp/kubernetes\"]" produced an unexpected new value:
.object.spec.template.spec.containers[0].resources.requests["memory"]: was cty.StringVal("2048Mi"), but now
cty.StringVal("2Gi").

This is a bug in the provider, which should be reported in the provider's own issue tracker.
```

디플로이먼트는 2048Mi의 메모리 요청을 지정하고, 쿠버네티스 API는 이를 읽기 쉽도록 2Gi로 다시 보고한다.
Kubernetes provider 는 이 경우를 처리하지 않으므로, 수정 방법은 istio.tf 파일의 값을 2Gi로 변경하는 것입니다.

# Null value conversion error

```shell
Error: API response status: Failure

  with kubernetes_manifest.deployment_istio_system_istio_ingressgateway,
  on istio.tf line 14211, in resource "kubernetes_manifest" "deployment_istio_system_istio_ingressgateway":
14211: resource "kubernetes_manifest" "deployment_istio_system_istio_ingressgateway" {

Deployment.apps "istio-ingressgateway" is invalid:
spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms: Required value: must
have at least one node selector term
```

문제는 널 값의 변환에 있습니다. 예를 들어, 이 YAML:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    preferredDuringSchedulingIgnoredDuringExecution:
```

이 다음과 같이 변환되었습니다:

```terraform
"affinity" = {
  "nodeAffinity" = {
    "preferredDuringSchedulingIgnoredDuringExecution" = null
    "requiredDuringSchedulingIgnoredDuringExecution" = null
  }
}
```

원본 YAML 파일은 빈 값이 있는 필드를 제거하기 때문에 kubectl에서 성공적으로 적용됩니다. 그러나 Terraform용 Kubernetes 공급자는 같은 방식으로 작동하지 않습니다. 값을 null로 설정하면 빈 필드를 Kubernetes API로 전송하여 위와 같은 오류가 발생합니다.

이 문제를 해결하려면 HCL 파일에서 null 값이 있는 모든 키를 제거해야 합니다. 제거 후 성공적으로 신청할 수 있습니다:

```shell
$ terraform apply

**Apply complete! Resources: 48 added, 0 changed, 0 destroyed.**
```

# Re-apply issues

플랜을 다시 실행하면 아무것도 변경하지 않았는데도 두 가지 변경 사항이 표시됩니다:

```shell
Terraform will perform the following actions:

  # module.istio.kubernetes_manifest.service_istio_system_istio_ingressgateway will be updated in-place
  ~ resource "kubernetes_manifest" "service_istio_system_istio_ingressgateway" {
      ~ object   = {
          ~ metadata   = {
              + annotations                = (known after apply)
                name                       = "istio-ingressgateway"
                # (13 unchanged attributes hidden)
            }
            # (3 unchanged attributes hidden)
        }
        # (1 unchanged attribute hidden)
    }

  # module.istio.kubernetes_manifest.validatingwebhookconfiguration_istio_validator_istio_system will be updated in-place
  ~ resource "kubernetes_manifest" "validatingwebhookconfiguration_istio_validator_istio_system" {
      ~ object   = {
          ~ webhooks   = [
              ~ {
                  ~ failurePolicy           = "Fail" -> "Ignore"
                    name                    = "rev.validation.istio.io"
                    # (9 unchanged attributes hidden)
                },
            ]
            # (3 unchanged attributes hidden)
        }
        # (1 unchanged attribute hidden)
    }

Plan: 0 to add, 2 to change, 0 to destroy.
```

이러한 변경 사항을 적용하려고 하면 다음 오류와 함께 실패합니다:

```shell
Error: There was a field manager conflict when trying to apply the manifest for "/istio-validator-istio-system"

  with module.istio.kubernetes_manifest.validatingwebhookconfiguration_istio_validator_istio_system,
  on istio/main.tf line 1173, in resource "kubernetes_manifest" "validatingwebhookconfiguration_istio_validator_istio_system":
1173: resource "kubernetes_manifest" "validatingwebhookconfiguration_istio_validator_istio_system" {

The API returned the following conflict: "Apply failed with 1 conflict: conflict with \"pilot-discovery\" using
admissionregistration.k8s.io/v1: .webhooks[name=\"rev.validation.istio.io\"].failurePolicy"

You can override this conflict by setting "force_conflicts" to true in the "field_manager" block.
```

force_conflicts = true 로 설정하는 제안된 수정 방법은 좋은 해결책이 아닙니다.
apply 할 수는 있지만 모든 apply 출력에 항상 동일한 변경 사항이 표시됩니다.

문제의 원인은 다음과 같은 설명이 있는 Istio YAML 매니페스트를 보면 알 수 있습니다:

```yaml
# Fail open until the validation webhook is ready. The webhook controller
# will update this to `Fail` and patch in the `caBundle` when the webhook
# endpoint is ready.
failurePolicy: Ignore
```

문제는 Istio 웹훅 컨트롤러가 배포 후 failPolicy를 변경하지만 이 상태 변경이 Terraform 상태에 반영되지 않는다는 것입니다.

이 문제를 해결하려면 ValidatingWebhookConfiguration 에서 failurePolicy를 주석 처리하여 Fail로 설정하면 됩니다:

```terraform
# shortened example
resource "kubernetes_manifest" "validatingwebhookconfiguration_istio_validator_istio_system" {
  manifest = {
    "apiVersion" = "admissionregistration.k8s.io/v1"
    "kind" = "ValidatingWebhookConfiguration"
    "webhooks" = [
      {
        "name" = "rev.validation.istio.io"
        // "failurePolicy" = "Ignore"
      }
    ]
  }
}
```

# Conclusion

Terraform Kubernetes provider 는 다음과 같은 경우에 애플리케이션 배포를 관리하는 데 좋은 옵션입니다:

- 간단한 인프라를 갖춘 소규모 팀
- 타사 애플리케이션을 위한 최소한의 사용자 지정 배포 사양 작성.
- 자주 업데이트하지 않는 애플리케이션

대규모 프로덕션 배포의 경우 좋은 옵션이라고 생각하지 않습니다.

- YAML을 HCL로 변환하는 데 시간이 너무 오래 걸립니다. tfk8과 같은 도구는 도움이 되지만 완벽하지는 않습니다. 성공적으로 적용하려면 시행착오를 거쳐야 합니다.
- 새 버전으로 업그레이드하는 것은 어렵습니다. 변환과 수정의 전체 과정을 반복해야 합니다.
- 테라폼 플랜을 실행하는 데 시간이 너무 오래 걸립니다. 몇 개의 타사 애플리케이션을 설치한 후 관리해야 할 리소스가 100개가 넘기 쉽습니다. ( -target 옵션을 사용할 수도 있지만 항상 올바른 리소스 이름을 찾아야 합니다).
- Kubernetes constantly reconciles 과 테라폼 스테이트 둘 모두 자체 상태를 관리하며 지속적으로 조정합니다. Kubernetes 상태의 모든 변경 사항은 Terraform 상태에서도 수동으로 변경해야 합니다. 위의 예시를 보면, 배포 후 Istio가 Kubernetes 리소스를 패치하면 Terraform은 항상 이를 되돌리려고 시도합니다.

다음 과정에서는 애플리케이션을 더 쉽게 설치할 수 있는 Terraform Helm 공급자에 대해 다룰 예정입니다.

# Mac OS Install Tip

tfk8s 설치

```shell
brew install tfk8s

```

istioctl 설치

```shell
brew install istioctl
```