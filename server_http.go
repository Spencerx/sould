package main

import (
	"fmt"
	"net/http"
	"os"
)

func (server *MirrorServer) ListenHTTP() error {
	http.Handle("/", server)

	return http.ListenAndServe(server.GetListenAddress(), nil)
}

func (server *MirrorServer) ServeHTTP(
	response http.ResponseWriter, request *http.Request,
) {
	defer func() {
		err := recover()
		if err != nil {
			logger.Errorf("(http) PANIC: %s\n%#v\n%s", err, request, stack())
		}
	}()

	logRequest(request)

	switch request.Method {
	case "POST":
		pullRequest, err := ExtractPullRequest(
			request.Form, server.insecureMode,
		)
		if err != nil {
			logger.Error(err)
			http.Error(response, err.Error(), http.StatusBadRequest)
			return
		}

		logger.Info(pullRequest)

		server.HandlePullRequest(response, pullRequest)

	case "GET":
		tarRequest, err := ExtractTarRequest(request.URL)
		if err != nil {
			logger.Error(err)
			http.Error(response, err.Error(), http.StatusBadRequest)
			return
		}

		logger.Info(tarRequest)

		server.HandleTarRequest(response, tarRequest)

	default:
		response.WriteHeader(http.StatusMethodNotAllowed)
		logger.Errorf("unsupported method: %s", request.Method)
	}
}

// GetMirror will try to get mirror from server storage directory and if can
// not, then will try to create mirror with given arguments.
func (server MirrorServer) GetMirror(
	name string, origin string,
) (mirror Mirror, created bool, err error) {
	mirror, err = GetMirror(server.GetStorageDir(), name)
	if err != nil {
		if !os.IsNotExist(err) {
			return Mirror{}, false, err
		}

		mirror, err = CreateMirror(server.GetStorageDir(), name, origin)
		if err != nil {
			return Mirror{}, false, NewError(err, "can't create new mirror")
		}

		return mirror, true, nil
	}

	mirrorURL, err := mirror.GetURL()
	if err != nil {
		return mirror, false, NewError(err, "can't get mirror origin url")
	}

	if mirrorURL != origin {
		return mirror, false, fmt.Errorf(
			"mirror have different origin url (%s)",
			mirrorURL,
		)
	}

	return mirror, true, nil
}
