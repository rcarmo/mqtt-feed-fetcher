(import
    [mimetools [Message :as parse-headers]]
    [gzip [GzipFile :as gzip-file]]
    [StringIO [StringIO :as string-io]]
    [urllib2 [Request HTTPError URLError urlopen BaseHandler addinfourl build-opener]])

(defclass not-modified-handler [BaseHandler]
    [[http-error-304 
        (fn [self req fp code message headers]
            (let [[result (addinfourl fp headers (.get-full-url req))]]
                (setv result.code code)
                    result))]])

(defn fetch-url [url &optional [etag nil] [last-modified nil] [timeout 2]]
    (let [[req (Request url)]
          [opener (build-opener (not-modified-handler))]]
        (.add-header req "User-Agent" "Mozilla/5.0")
        (.add-header req "Accept-encoding" "gzip")
        (if etag
            (.add-header req "If-None-Match" etag))
        (if last-modified 
            (.add-header req "Last-Modified" last-modified))
        (try 
            (let [[response (.open opener req nil timeout)]
                  [headers (dict ( .info response))]
                  [data (.read response)]
                  [code response.code]]
                (if (= "gzip" (.get headers "content-encoding" nil))
                     {:headers headers
                      :data (.read (apply gzip-file [] {"fileobj" (string-io data)}))
                      :code code}
                     {:headers headers
                      :data data
                     :code code}))
            (catch [e HTTPError]
                {:headers (dict (parse-headers (string-io e.headers)))
                :data e.reason
                :code e.code})
            (catch [e URLError]
                {:headers {}
                :data (unicode e.reason)
                :code 598})
            (catch [e Exception]
                {:headers {}
                :data (unicode e)
                :code 599})))) ; "Network connect timeout error"
