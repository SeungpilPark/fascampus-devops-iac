# 기본 사항
헬름 공급자는 helm_release 라는 리소스를 하나만 가지고 있다. 예를 들어 다음과 같이 구성하고 이를 사용하여 Grafana를 설치할 수 있습니다

```terraform
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "helm_release" "grafana" {
  name             = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  version          = "7.0.6"
}
```

이를 적용하면 테라폼 리소스가 생성됩니다:

```shell
$ terraform apply
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

그리고 Kubernetes에 애플리케이션을 배포합니다:

```shell
$ kubectl get pods
NAME                       READY   STATUS    RESTARTS   AGE
grafana-5b67f46b65-pq25z   1/1     Running   0          76s
```

# Istio 설치

이전 포스트에서는 쿠버네티스 공급자를 사용하여 Istio를 설치했습니다. 두 공급자의 차이점을 보여드리기 위해 이번에는 헬름 공급자를 사용하여 Istio를 다시 설치해 보겠습니다.

지난번에 우리는 istioctl을 사용하여 CRD와 Istiod 배포를 포함하는 Istio YAML 매니페스트를 생성했습니다. 헬름으로 동일한 리소스를 배포하려면 두 개의 차트를 설치해야 합니다:

- CRD가 포함된 기본 차트입니다.
- istiod 배포가 포함된 istiod 차트입니다.

Terraform에서는 다음과 같이 설치할 수 있습니다:

```terraform
resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = true
  version          = "1.20.0"
}

resource "helm_release" "istiod" {
  name             = "istiod"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "istiod"
  namespace        = "istio-system"
  create_namespace = true
  version          = "1.20.0"

  # to install the CRDs first
  depends_on = [helm_release.istio_base]
}
```

적용합니다.

```shell
$ terraform apply

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

```shell
$ kubectl get pods -n istio-system
NAME                      READY   STATUS    RESTARTS   AGE
istiod-7d4885fc54-qgk54   1/1     Running   0          37s
```

Kubernetes 공급자를 사용할 때와 비교하면 훨씬 더 쉽고 빨랐습니다. YAML을 HCL로 변환한 다음 CRD를 수동으로 다른 파일로 분할할 필요가 없었습니다.

# Chart values

사용자 지정 차트 값을 설정하는 3가지 옵션이 있습니다:

- HCL set blocks
- HCL set_sensitive blocks
- YAML/JSON in the values attribute
- 
각각의 방법을 살펴보고 어떻게 사용할 수 있는지, 각 방법의 장단점은 무엇인지 알아보겠습니다.

# HCL set blocks

다음은 위에서와 동일한 Istio 차트에서 집합을 사용하여 사용자 지정 값을 설정하는 방법입니다:

```terraform
resource "helm_release" "istiod" {
  # ...

  set {
    name  = "pilot.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "pilot.resources.requests.memory"
    value = "100Mi"
  }

  set {
    name  = "pilot.resources.limits.memory"
    value = "100Mi"
  }
}
```

{}, [], . 및 , 문자가 포함된 값을 설정할 때는 이중 이스케이프 처리해야 합니다:

```terraform
set { name = "pilot.podAnnotations.prometheus\\.io/scrape" value = "\"true\""}
```

이 방법의 단점은 장황하다는 것입니다. 각 값은 4줄을 차지합니다. HCL은 이를 한 줄로 병합하는 것을 허용하지 않습니다:

```shell
Error: Invalid single-argument block definition

  on main.tf line 28, in resource "helm_release" "istiod":
  28:   set { name  = "pilot.resources.requests.memory", value = "100Mi" }

Single-line block syntax can include only one argument definition. To define multiple
arguments, use the multi-line block syntax with one argument definition per line.
```

단일 줄 블록 구문은 하나의 인수 정의만 포함할 수 있습니다.여러 인수를 정의하려면 한줄에 하나의 인수 정의가 있는 여러 줄 블록 구문을 사용합니다.
즉, 헬름 차트에 3개의 사용자 정의 값을 설정하려면 테라폼 파일에 12줄을 추가해야 합니다. 이렇게 하면 차트가 커지면 빠르게 합산되어 변경 사항을 제대로 파악하기 어려울 수 있습니다.

# HCL set_sensitive blocks

플랜 출력에서 일반 텍스트로 표시되지 않아야 하는 민감한 값(비밀)의 경우, HCL set_sensitive 블록을 사용해야 합니다.
Grafana 헬름 차트를 사용하여 다음과 같이 관리자 비밀번호를 설정할 수 있습니다:

```terraform
set_sensitive {
  name  = "grafana.adminPassword"
  value = local.password
}
```

다음 예제에서는 Grafana Helm 차트를 사용하여 GitHub OAuth2 인증에 대한 클라이언트 비밀을 설정합니다:

```terraform
resource "helm_release" "grafana" {
  name             = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  version          = "7.0.6"
  namespace        = "grafana"
  create_namespace = true

  set {
    name = "grafana\\.ini.server.root_url"
    value = "htps://example.org"
  }

  set_sensitive {
    name = "grafana\\.ini.server.auth\\.github.client_secret"
    value = "very-secret"
  }
}
```

처음 적용할 때는 민감한 값이 표시되지 않지만 리소스의 속성을 변경하면(아래에서는 root_url 을 변경했습니다) 해당 속성이 일반 텍스트로 표시됩니다:

```shell
# helm_release.grafana will be updated in-place
~ resource "helm_release" "grafana" {
      id                         = "grafana"
    ~ metadata                   = [
        - {
            - app_version = "10.1.5"
            - chart       = "grafana"
            - name        = "grafana"
            - namespace   = "grafana"
            - revision    = 3
            - values      = jsonencode(
                  {
                    - "grafana.ini" = {
                        - server = {
                            - "auth.github" = {
                                - client_secret = "very-secret"
                              }
                            - root_url      = "htps://example.org"
                          }
                      }
                  }
              )
            - version     = "7.0.6"
          },
      ] -> (known after apply)
      name                       = "grafana"
      # (27 unchanged attributes hidden)

    - set {
        - name  = "grafana\\.ini.server.root_url" -> null
        - value = "htps://example.org" -> null
      }
    + set {
        + name  = "grafana\\.ini.server.root_url"
        + value = "htps://www.grafana.com"
      }

      # (1 unchanged block hidden)
  }
```
출력에서 very-secret 값이 일반 텍스트로 유출되는 것을 확인할 수 있습니다.

# YAML in values attribute

HCL 집합 블록을 사용하는 대신 값 인수를 설정하여 YAML 또는 JSON으로 값을 지정할 수 있습니다. 아래 예제에서는 YAML을 중심으로 설명하겠습니다.

가장 일반적으로 HCL heredoc 문자열이 사용됩니다. 예를 들어 Istio 헬름 차트를 사용합니다:

```terraform
values = [<<EOT
pilot:
  resources:
    requests:
      cpu: "100m"
      memory: "100Mi"
    limits:
      memory: "100Mi"
EOT
]
```

이것은 HCL 세트 블록보다 더 간결하고 가독성이 좋습니다. 또한 헬름 차트 설명서나 YAML로 작성된 기본값 파일에서 예제를 쉽게 복사하여 붙여넣을 수 있습니다.

그러나 이 접근 방식의 단점은 속성이 HCL 텍스트 필드이기 때문에 편집기에 보푸라기, 구문 강조 표시 또는 스키마 유효성 검사가 없다는 것입니다. 이로 인해 들여쓰기 오류와 같은 일반적인 오류가 발생할 수 있습니다.

한 가지 해결책은 별도의 YAML 파일에서 값을 읽는 것입니다:

```terraform
values = [file("${path.module}/values.yaml")]
```

이렇게 하면 에디터에서 YAML 파일을 열고 언어 지원을 받을 수 있습니다. 또 다른 이점은 Terraform과 동일한 값을 사용할 수 있기 때문에 헬름 차트를 로컬로 렌더링할 때 디버깅이 더 쉬워진다는 점입니다.

이 방법의 단점은 대체(YAML 파일의 변수 사용)를 허용하지 않는다는 것입니다. 이는 테라폼 리소스의 출력을 헬름 차트 리소스의 입력으로 사용하고자 할 때 중요하다.

이 문제를 해결하기 위해 YAML 파일을 템플릿으로 렌더링하고 변수에 값을 전달할 수 있습니다.

다음 예제에서는 Cloudflare로 DNS 레코드를 생성한 다음 Grafana Helm 차트 YAML 값의 호스트 이름 출력을 사용합니다:

```terraform
resource "cloudflare_record" "cluster" {
  zone_id = "000"
  name    = "cluster"
  value   = "192.0.2.1"
  type    = "A"
}

resource "helm_release" "grafana" {
  name             = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  version          = "7.0.0"

  values = [templatefile("values.yaml", {
    root_url = "https://${cloudflare_record.cluster.hostname}"
  })]
}
```

values.yaml 파일:

```yaml
grafana.ini:
  server:
    root_url: ${root_url}
```

단점은 이제 두 개의 파일을 관리하고 HCL 구성 파일과 관련 YAML 파일 간의 변경 사항을 조정해야 하므로 오류가 발생할 가능성이 높아질 수 있다는 점입니다.

# HCL objects instead of text

값을 설정하는 또 다른 방법은 HCL 객체를 사용하고 jsonencode 또는 yamlencode를 사용하여 인코딩하는 것입니다. 집합 블록보다는 덜 장황하지만 YAML보다는 약간 더 장황합니다. 장점은 모든 것을 하나의 파일에 보관할 수 있고 대체가 가능하며 편집기 언어를 지원한다는 점입니다.

다음 예제는 Istio 헬름 차트에 대한 리소스 요청/제한을 설정합니다:

```terraform
values = [
  jsonencode({
    pilot = {
      resources = {
        requests = {
            cpu = "100m"
            memory = "100Mi"
          }
          limits = {
            memory = "100Mi"
          }
      }
    }
  })
]
```

단점은 다른 HCL 블록과 동일합니다. 가장 큰 문제는 문서나 예제의 YAML 코드를 HCL 객체로 변환해야 한다는 것입니다. 이 추가 단계로 인해 개발 속도가 느려지고 변환할 때 오류가 발생할 수 있습니다.

# Diff output

위의 값 설정 방법에서 가장 눈에 띄는 차이점은 테라폼 플랜을 실행할 때의 출력 차이입니다.

일반적으로 HCL 세트 블록은 변경된 내용을 명확하게 보여줍니다. 메모리 제한 값을 변경할 때의 계획 출력은 다음과 같습니다:

```shell
- set {
    - name  = "pilot.resources.limits.memory" -> null
    - value = "100Mi" -> null
  }
+ set {
    + name  = "pilot.resources.limits.memory"
    + value = "150Mi"
  }
```

그러나 값 속성은 일반 텍스트로 취급되며 값을 변경하면 항상 전체 속성이 변경된 것으로 표시됩니다. 메모리 제한 값을 변경하면 출력은 다음과 같이 표시됩니다:

```shell
~ values = [
  - <<-EOT
      pilot:
        resources:
          requests:
            cpu: "100m"
            memory: "100Mi"
          limits:
            memory: "100Mi"
  EOT,
  + <<-EOT
      pilot:
        resources:
          requests:
            cpu: "100m"
            memory: "100Mi"
          limits:
            memory: "150Mi"
  EOT,
]
```

코드를 검토할 때 실제 변경 사항을 확인하기가 어렵습니다. 테라폼 계획 결과를 댓글로 게시하는 Atlantis 와 같은 풀 리퀘스트 자동화 도구를 사용하는 프로젝트는 덜 유용할 것입니다. 


# Fixing issues when client aborts

클라이언트가 네트워크 연결이 끊어지는 등의 이유로 애플리케이션을 중단해야 하는 경우 리소스는 업그레이드 보류 상태가 되어 애플리케이션을 다시 실행할 수 없게 됩니다.

예를 들어 다음과 같이 헬름 공급자를 사용하여 Argo CD를 설치했다면:

```terraform
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.51.0"
  namespace        = "default"
}
```

그런 다음 버전을 5.51.1로 업데이트하고 적용 과정에서 Ctrl+C를 누릅니다:

```shell
helm_release.argocd: Still modifying... [id=argocd, 10s elapsed]
^C
Two interrupts received. Exiting immediately. Note that data loss may have occurred.

│ Error: operation canceled
```

다음에 apply 를 재 실행하면 다음과 같은 오류가 발생합니다:

```shell
│ Error: another operation (install/upgrade/rollback) is in progress
│
│   with helm_release.argocd,
│   on main.tf line 29, in resource "helm_release" "argocd":
│   29: resource "helm_release" "argocd" {
```

헬름에서 이 릴리스를 위해 만든 최신 시크릿을 삭제하면 이 문제를 해결할 수 있다:

```shell
$ kubectl get secret
NAME                           TYPE                 DATA   AGE
sh.helm.release.v1.argocd.v1   helm.sh/release.v1   1      45m
sh.helm.release.v1.argocd.v2   helm.sh/release.v1   1      40m
sh.helm.release.v1.argocd.v3   helm.sh/release.v1   1      32m

$ kubectl delete secret sh.helm.release.v1.argocd.v3
```

그 후 apply 가 다시 작동합니다. 비슷한 오류 `Error: cannot re-use a name that is still in use` 도 같은 방법으로 수정할 수 있습니다.

# Conclusion

이 과정에서는 Terraform Helm 공급자를 사용하는 방법을 살펴봤습니다. 사용 방법에 대한 기본 사항을 다루고 다양한 방식으로 사용자 정의 헬름 차트 값을 설정하는 방법을 보여드렸습니다.

일반적으로 이 공급자는 지난 블로그 포스트에서 소개한 Kubernetes 공급자보다 훨씬 쉽게 Kubernetes 리소스를 배포할 수 있게 해줍니다. YAML을 HCL로 수동으로 변환할 필요도 없고, 특별한 방식으로 CRD를 처리할 필요도 없습니다.