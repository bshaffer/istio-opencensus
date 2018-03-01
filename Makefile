#	Copyright 2018, Google, Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
PROJECT_ID=$(shell gcloud config list project --format=flattened | awk 'FNR == 1 {print $$2}')
ZONE=us-west1-b
JAEGER_POD_NAME=$(shell kubectl -n istio-system get pod -l app=jaeger -o jsonpath='{.items[0].metadata.name}')
SERVICEGRAPH_POD_NAME=$(shell kubectl -n istio-system get pod -l app=servicegraph -o jsonpath='{.items[0].metadata.name}')
GRAFANA_POD_NAME=$(shell kubectl -n istio-system get pod -l app=grafana -o jsonpath='{.items[0].metadata.name}')
PROMETHEUS_POD_NAME=$(shell kubectl -n istio-system get pod -l app=prometheus -o jsonpath='{.items[0].metadata.name}')
create-cluster:
	gcloud beta container --project "$(PROJECT_ID)" clusters create "my-istio-cluster" --zone "$(ZONE)" --username="admin" --machine-type "n1-standard-1" --image-type "COS" --disk-size "100" --scopes "https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --enable-kubernetes-alpha --num-nodes "4" --network "default" --enable-cloud-logging --enable-cloud-monitoring --enable-legacy-authorization
deploy-infra:
	kubectl apply -f 'https://raw.githubusercontent.com/istio/istio/4bc1381/install/kubernetes/istio.yaml'
	kubectl apply -f 'https://raw.githubusercontent.com/istio/istio/4bc1381/install/kubernetes/istio-initializer.yaml'
	kubectl apply -n istio-system -f 'https://raw.githubusercontent.com/jaegertracing/jaeger-kubernetes/master/all-in-one/jaeger-all-in-one-template.yml'
	kubectl apply -f './config/prometheus.yaml'
	kubectl apply -f 'https://raw.githubusercontent.com/istio/istio/4bc1381/install/kubernetes/addons/servicegraph.yaml'
	kubectl apply -f 'https://raw.githubusercontent.com/istio/istio/4bc1381/install/kubernetes/addons/grafana.yaml'
deploy-stuff:
	kubectl apply -f ./config/config.yaml
	kubectl apply -f ./config/services.yaml
	-sed -e 's~<PROJECT_ID>~$(PROJECT_ID)~g' ./config/deployment.yaml | kubectl apply -f -
get-stuff:
	kubectl get pods && kubectl get svc && kubectl get ingress


start-monitoring-services:
	$(shell kubectl -n istio-system port-forward $(JAEGER_POD_NAME) 16686:16686 & kubectl -n istio-system port-forward $(SERVICEGRAPH_POD_NAME) 8088:8088 & kubectl -n istio-system port-forward $(GRAFANA_POD_NAME) 3000:3000 & kubectl -n istio-system port-forward $(PROMETHEUS_POD_NAME) 9090:9090)
build-full:
	docker build -t gcr.io/$(PROJECT_ID)/trace:go ./code/
build-simple:
	docker build -t gcr.io/$(PROJECT_ID)/trace:go ./simple-code/
push:
	gcloud docker -- push gcr.io/$(PROJECT_ID)/trace:go
run-local:
	docker run -ti -p 3000:3000 gcr.io/$(PROJECT_ID)/trace:go
restart-all:
	kubectl delete pods --all
get-logs:
	kubectl logs --tail=9 $(shell kubectl get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}') frontend
	kubectl logs --tail=9 $(shell kubectl get pod -l app=middleware -o jsonpath='{.items[0].metadata.name}') middleware
	kubectl logs --tail=9 $(shell kubectl get pod -l app=backend -o jsonpath='{.items[0].metadata.name}') backend
stop-all:
	kubectl delete deployments --all
	kubectl -n istio-system delete pods --all
delete-cluster:
	kubectl delete service frontend
	kubectl delete ingress istio-ingress
	gcloud container clusters delete "my-istio-cluster" --zone "$(ZONE)"