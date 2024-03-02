oc project book-info
# elevate service accounts
oc adm policy add-scc-to-user anyuid -z bookinfo-details
oc adm policy add-scc-to-user anyuid -z bookinfo-productpage
oc adm policy add-scc-to-user anyuid -z bookinfo-ratings
oc adm policy add-scc-to-user anyuid -z bookinfo-reviews
# add secret to sa
oc secrets link --for=pull bookinfo-details dso-quay-user
oc secrets link --for=pull bookinfo-productpage dso-quay-user
oc secrets link --for=pull bookinfo-ratings dso-quay-user
oc secrets link --for=pull bookinfo-reviews dso-quay-user
