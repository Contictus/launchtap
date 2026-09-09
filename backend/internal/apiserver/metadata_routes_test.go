package apiserver

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/metadata"
	"github.com/Contictus/launchtap/backend/internal/privyauth"
	"github.com/ethereum/go-ethereum/common"
)

type fakeVerifier struct {
	principal privyauth.Principal
	err       error
}

func (v fakeVerifier) Verify(context.Context, string, string) (privyauth.Principal, error) {
	return v.principal, v.err
}

type fakeMetadataStore struct {
	metadata metadata.Metadata
	image    metadata.Image
	err      error
}

func (s *fakeMetadataStore) ReplaceMetadata(_ context.Context, _ int64, _ common.Address, _ []common.Address, value metadata.Metadata) (int64, error) {
	if s.err != nil {
		return 0, s.err
	}
	s.metadata = value
	return value.Revision + 1, nil
}
func (s *fakeMetadataStore) ReplaceImage(_ context.Context, _ int64, _ common.Address, _ []common.Address, value metadata.Image) (int64, error) {
	if s.err != nil {
		return 0, s.err
	}
	s.image = value
	return value.Revision + 1, nil
}
func (s *fakeMetadataStore) GetImage(context.Context, int64, common.Address) (metadata.Image, error) {
	if s.err != nil {
		return metadata.Image{}, s.err
	}
	return s.image, nil
}

func TestMetadataAndImageHTTPContracts(t *testing.T) {
	store := &fakeMetadataStore{}
	creator := common.HexToAddress("0x00000000000000000000000000000000000000aa")
	server := New(DefaultConfig(), ReadyFunc(func(context.Context) error { return nil }), nil)
	server.RegisterMetadataRoutes(MetadataRoutes{Store: store, Verifier: fakeVerifier{principal: privyauth.Principal{PrivyDID: "did:privy:test", Wallets: []common.Address{creator}}}, ChainID: 46630})
	token := "0x00000000000000000000000000000000000000bb"

	request := httptest.NewRequest(http.MethodPut, "/v1/tokens/"+token+"/metadata", strings.NewReader(`{"description":"plain text","x_url":"https://x.com/test","telegram_url":"https://t.me/test"}`))
	request.Header.Set("Content-Type", "application/json")
	authorize(request)
	request.Header.Set("If-Match", `"0"`)
	response := httptest.NewRecorder()
	server.Handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK || response.Header().Get("ETag") != `"1"` || store.metadata.Description != "plain text" {
		t.Fatalf("metadata status=%d headers=%v body=%s stored=%+v", response.Code, response.Header(), response.Body.String(), store.metadata)
	}

	png := append([]byte("\x89PNG\r\n\x1a\n"), bytes.Repeat([]byte{1}, 32)...)
	request = httptest.NewRequest(http.MethodPut, "/v1/tokens/"+token+"/image", bytes.NewReader(png))
	request.Header.Set("Content-Type", "image/png")
	authorize(request)
	request.Header.Set("If-Match", "0")
	response = httptest.NewRecorder()
	server.Handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK || store.image.ContentType != "image/png" || !bytes.Equal(store.image.Content, png) {
		t.Fatalf("image write status=%d body=%s stored=%+v", response.Code, response.Body.String(), store.image)
	}

	request = httptest.NewRequest(http.MethodGet, "/v1/tokens/"+token+"/image", nil)
	response = httptest.NewRecorder()
	server.Handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK || response.Header().Get("Content-Type") != "image/png" || response.Header().Get("Content-Length") != strconv.Itoa(len(png)) || response.Header().Get("X-Content-Type-Options") != "nosniff" || !bytes.Equal(response.Body.Bytes(), png) {
		t.Fatalf("image read status=%d headers=%v body=%x", response.Code, response.Header(), response.Body.Bytes())
	}
	etag := response.Header().Get("ETag")
	request = httptest.NewRequest(http.MethodGet, "/v1/tokens/"+token+"/image", nil)
	request.Header.Set("If-None-Match", etag)
	response = httptest.NewRecorder()
	server.Handler.ServeHTTP(response, request)
	if response.Code != http.StatusNotModified || response.Body.Len() != 0 {
		t.Fatalf("conditional read status=%d body=%x", response.Code, response.Body.Bytes())
	}
	for _, validator := range []string{"*", "W/" + etag} {
		request = httptest.NewRequest(http.MethodGet, "/v1/tokens/"+token+"/image", nil)
		request.Header.Set("If-None-Match", validator)
		response = httptest.NewRecorder()
		server.Handler.ServeHTTP(response, request)
		if response.Code != http.StatusNotModified {
			t.Fatalf("conditional validator=%q status=%d", validator, response.Code)
		}
	}
}

func TestSubjectLimiterBoundsIdentityState(t *testing.T) {
	limiter := NewSubjectLimiter(1, time.Minute)
	now := time.Unix(1_000, 0)
	for index := 0; index < maxSubjectLimiterEntries; index++ {
		if !limiter.Allow(strconv.Itoa(index), now) {
			t.Fatalf("entry %d rejected before capacity", index)
		}
	}
	if limiter.Allow("overflow", now) {
		t.Fatal("limiter accepted an unbounded identity entry")
	}
	if !limiter.Allow("replacement", now.Add(time.Minute)) || len(limiter.entries) != 1 {
		t.Fatalf("expired entries were not pruned: entries=%d", len(limiter.entries))
	}
}

func TestMetadataAuthenticationAuthorizationAndValidationProblems(t *testing.T) {
	token := "0x00000000000000000000000000000000000000bb"
	tests := []struct {
		name     string
		verifier privyauth.Verifier
		storeErr error
		body     string
		want     int
	}{
		{"authentication", fakeVerifier{err: privyauth.ErrInvalidCredentials}, nil, `{}`, http.StatusUnauthorized},
		{"authorization", fakeVerifier{principal: privyauth.Principal{PrivyDID: "did", Wallets: []common.Address{common.HexToAddress("0x01")}}}, metadata.ErrUnauthorized, `{}`, http.StatusForbidden},
		{"revision", fakeVerifier{principal: privyauth.Principal{PrivyDID: "did"}}, metadata.ErrRevisionConflict, `{}`, http.StatusConflict},
		{"description", fakeVerifier{principal: privyauth.Principal{PrivyDID: "did"}}, nil, `{"description":"` + strings.Repeat("x", 2001) + `"}`, http.StatusUnprocessableEntity},
		{"url", fakeVerifier{principal: privyauth.Principal{PrivyDID: "did"}}, nil, `{"x_url":"http://x.com/test"}`, http.StatusUnprocessableEntity},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			store := &fakeMetadataStore{err: test.storeErr}
			server := New(DefaultConfig(), ReadyFunc(func(context.Context) error { return nil }), nil)
			server.RegisterMetadataRoutes(MetadataRoutes{Store: store, Verifier: test.verifier, ChainID: 1})
			request := httptest.NewRequest(http.MethodPut, "/v1/tokens/"+token+"/metadata", strings.NewReader(test.body))
			request.Header.Set("Content-Type", "application/json")
			authorize(request)
			request.Header.Set("If-Match", "0")
			response := httptest.NewRecorder()
			server.Handler.ServeHTTP(response, request)
			if response.Code != test.want {
				body, _ := io.ReadAll(response.Body)
				t.Fatalf("status=%d want=%d body=%s", response.Code, test.want, body)
			}
		})
	}
}

func TestMetadataMissingCredentialsIsUnauthorized(t *testing.T) {
	server := New(DefaultConfig(), ReadyFunc(func(context.Context) error { return nil }), nil)
	server.RegisterMetadataRoutes(MetadataRoutes{Store: &fakeMetadataStore{}, Verifier: fakeVerifier{}, ChainID: 1})
	request := httptest.NewRequest(http.MethodPut, "/v1/tokens/0x00000000000000000000000000000000000000bb/metadata", strings.NewReader(`{}`))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("If-Match", "0")
	response := httptest.NewRecorder()
	server.Handler.ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d want=%d body=%s", response.Code, http.StatusUnauthorized, response.Body.String())
	}
}

func TestImageRejectsActiveMismatchAndOversizeContent(t *testing.T) {
	store := &fakeMetadataStore{}
	server := New(DefaultConfig(), ReadyFunc(func(context.Context) error { return nil }), nil)
	server.RegisterMetadataRoutes(MetadataRoutes{Store: store, Verifier: fakeVerifier{principal: privyauth.Principal{PrivyDID: "did"}}, ChainID: 1})
	for _, test := range []struct {
		name, contentType string
		body              []byte
		want              int
	}{
		{"svg", "image/svg+xml", []byte(`<svg></svg>`), http.StatusUnsupportedMediaType},
		{"mismatch", "image/jpeg", []byte("\x89PNG\r\n\x1a\nbody"), http.StatusUnsupportedMediaType},
		{"oversize", "image/png", bytes.Repeat([]byte{0}, maxImageBytes+1), http.StatusRequestEntityTooLarge},
	} {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodPut, "/v1/tokens/0x00000000000000000000000000000000000000bb/image", bytes.NewReader(test.body))
			request.Header.Set("Content-Type", test.contentType)
			authorize(request)
			request.Header.Set("If-Match", "0")
			response := httptest.NewRecorder()
			server.Handler.ServeHTTP(response, request)
			if response.Code != test.want {
				t.Fatalf("status=%d want=%d body=%s", response.Code, test.want, response.Body.String())
			}
		})
	}
}

func authorize(request *http.Request) {
	request.Header.Set("Authorization", "Bearer access.token.value")
	request.Header.Set("privy-id-token", "identity.token.value")
}

var _ metadata.Store = (*fakeMetadataStore)(nil)
var _ privyauth.Verifier = fakeVerifier{}
