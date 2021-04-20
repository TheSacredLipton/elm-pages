module DataSource.Http exposing
    ( RequestDetails
    , get, request
    , Body, emptyBody, stringBody, jsonBody
    , unoptimizedRequest
    , Expect, expectString, expectUnoptimizedJson
    , andThen
    )

{-| StaticHttp requests are an alternative to doing Elm HTTP requests the traditional way using the `elm/http` package.

The key differences are:

  - `StaticHttp.Request`s are performed once at build time (`Http.Request`s are performed at runtime, at whenever point you perform them)
  - `StaticHttp.Request`s strip out unused JSON data from the data your decoder doesn't touch to minimize the JSON payload
  - `StaticHttp.Request`s can use [`Pages.Secrets`](Pages.Secrets) to securely use credentials from your environment variables which are completely masked in the production assets.
  - `StaticHttp.Request`s have a built-in `StaticHttp.andThen` that allows you to perform follow-up requests without using tasks


## Scenarios where StaticHttp is a good fit

If you need data that is refreshed often you may want to do a traditional HTTP request with the `elm/http` package.
The kinds of situations that are served well by static HTTP are with data that updates moderately frequently or infrequently (or never).
A common pattern is to trigger a new build when data changes. Many JAMstack services
allow you to send a WebHook to your host (for example, Netlify is a good static file host that supports triggering builds with webhooks). So
you may want to have your site rebuild everytime your calendar feed has an event added, or whenever a page or article is added
or updated on a CMS service like Contentful.

In scenarios like this, you can serve data that is just as up-to-date as it would be using `elm/http`, but you get the performance
gains of using `StaticHttp.Request`s as well as the simplicity and robustness that comes with it. Read more about these benefits
in [this article introducing StaticHttp requests and some concepts around it](https://elm-pages.com/blog/static-http).


## Scenarios where StaticHttp is not a good fit

  - Data that is specific to the logged-in user
  - Data that needs to be the very latest and changes often (for example, sports scores)

@docs RequestDetails
@docs get, request


## Building a StaticHttp Request Body

The way you build a body is analogous to the `elm/http` package. Currently, only `emptyBody` and
`stringBody` are supported. If you have a use case that calls for a different body type, please open a Github issue
and describe your use case!

@docs Body, emptyBody, stringBody, jsonBody


## Unoptimized Requests

Warning - use these at your own risk! It's highly recommended that you use the other request functions that make use of
`zwilias/json-decode-exploration` in order to allow you to reduce down your JSON to only the values that are used by
your decoders. This can significantly reduce download sizes for your StaticHttp requests.

@docs unoptimizedRequest


### Expect for unoptimized requests

@docs Expect, expectString, expectUnoptimizedJson

-}

import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Dict.Extra
import Internal.OptimizedDecoder
import Json.Decode
import Json.Decode.Exploration
import Json.Encode as Encode
import OptimizedDecoder as Decode exposing (Decoder)
import Pages.Internal.ApplicationType as ApplicationType exposing (ApplicationType)
import Pages.Internal.StaticHttpBody as Body
import Pages.Secrets
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest exposing (RawRequest(..))
import RequestsAndPending exposing (RequestsAndPending)
import Secrets


{-| Build an empty body for a StaticHttp request. See [elm/http's `Http.emptyBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#emptyBody).
-}
emptyBody : Body
emptyBody =
    Body.EmptyBody


{-| Builds a string body for a StaticHttp request. See [elm/http's `Http.stringBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#stringBody).

Note from the `elm/http` docs:

> The first argument is a [MIME type](https://en.wikipedia.org/wiki/Media_type) of the body. Some servers are strict about this!

-}
stringBody : String -> String -> Body
stringBody contentType content =
    Body.StringBody contentType content


{-| Builds a JSON body for a StaticHttp request. See [elm/http's `Http.jsonBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#jsonBody).
-}
jsonBody : Encode.Value -> Body
jsonBody content =
    Body.JsonBody content


{-| A body for a StaticHttp request.
-}
type alias Body =
    Body.Body


lookup : ApplicationType -> DataSource value -> RequestsAndPending -> Result Pages.StaticHttpRequest.Error ( Dict String String, value )
lookup =
    lookupHelp Dict.empty


lookupHelp : Dict String String -> ApplicationType -> DataSource value -> RequestsAndPending -> Result Pages.StaticHttpRequest.Error ( Dict String String, value )
lookupHelp strippedSoFar appType requestInfo rawResponses =
    case requestInfo of
        Request ( urls, lookupFn ) ->
            lookupFn appType rawResponses
                |> Result.andThen
                    (\( strippedResponses, nextRequest ) ->
                        lookupHelp (Dict.union strippedResponses strippedSoFar)
                            appType
                            (addUrls urls nextRequest)
                            rawResponses
                    )

        Done value ->
            Ok ( strippedSoFar, value )


addUrls : List (Pages.Secrets.Value HashRequest.Request) -> DataSource value -> DataSource value
addUrls urlsToAdd requestInfo =
    case requestInfo of
        Request ( initialUrls, function ) ->
            Request ( initialUrls ++ urlsToAdd, function )

        Done value ->
            Done value


lookupUrls : DataSource value -> List (Pages.Secrets.Value RequestDetails)
lookupUrls requestInfo =
    case requestInfo of
        Request ( urls, _ ) ->
            urls

        Done _ ->
            []


{-| Build off of the response from a previous `StaticHttp` request to build a follow-up request. You can use the data
from the previous response to build up the URL, headers, etc. that you send to the subsequent request.

    import DataSource
    import Json.Decode as Decode exposing (Decoder)

    licenseData : StaticHttp.Request String
    licenseData =
        StaticHttp.get
            (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
            (Decode.at [ "license", "url" ] Decode.string)
            |> StaticHttp.andThen
                (\licenseUrl ->
                    StaticHttp.get (Secrets.succeed licenseUrl) (Decode.field "description" Decode.string)
                )

-}
andThen : (a -> DataSource b) -> DataSource a -> DataSource b
andThen fn requestInfo =
    Request
        ( lookupUrls requestInfo
        , \appType rawResponses ->
            lookup appType
                requestInfo
                rawResponses
                |> (\result ->
                        case result of
                            Err error ->
                                Err error

                            Ok ( strippedResponses, value ) ->
                                ( strippedResponses, fn value ) |> Ok
                   )
        )


{-| A simplified helper around [`StaticHttp.request`](#request), which builds up a StaticHttp GET request.

    import DataSource
    import Json.Decode as Decode exposing (Decoder)

    getRequest : StaticHttp.Request Int
    getRequest =
        StaticHttp.get
            (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
            (Decode.field "stargazers_count" Decode.int)

-}
get :
    Pages.Secrets.Value String
    -> Decoder a
    -> DataSource a
get url decoder =
    request
        (Secrets.map
            (\okUrl ->
                -- wrap in new variant
                { url = okUrl
                , method = "GET"
                , headers = []
                , body = emptyBody
                }
            )
            url
        )
        decoder


{-| The full details to perform a StaticHttp request.
-}
type alias RequestDetails =
    { url : String
    , method : String
    , headers : List ( String, String )
    , body : Body
    }


requestToString : RequestDetails -> String
requestToString requestDetails =
    requestDetails.url


{-| Build a `StaticHttp` request (analagous to [Http.request](https://package.elm-lang.org/packages/elm/http/latest/Http#request)).
This function takes in all the details to build a `StaticHttp` request, but you can build your own simplified helper functions
with this as a low-level detail, or you can use functions like [StaticHttp.get](#get).
-}
request :
    Pages.Secrets.Value RequestDetails
    -> Decoder a
    -> DataSource a
request urlWithSecrets decoder =
    unoptimizedRequest urlWithSecrets (ExpectJson decoder)


{-| Analgous to the `Expect` type in the `elm/http` package. This represents how you will process the data that comes
back in your StaticHttp request.

You can derive `ExpectUnoptimizedJson` from `ExpectString`. Or you could build your own helper to process the String
as XML, for example, or give an `elm-pages` build error if the response can't be parsed as XML.

-}
type Expect value
    = ExpectUnoptimizedJson (Json.Decode.Decoder value)
    | ExpectJson (Decoder value)
    | ExpectString (String -> Result String value)


{-| Request a raw String. You can validate the String if you need to check the formatting, or try to parse it
in something besides JSON. Be sure to use the `StaticHttp.request` function if you want an optimized request that
strips out unused JSON to optimize your asset size.

If the function you pass to `expectString` yields an `Err`, then you will get at StaticHttpDecodingError that will
fail your `elm-pages` build and print out the String from the `Err`.

    request =
        StaticHttp.unoptimizedRequest
            (Secrets.succeed
                { url = "https://example.com/file.txt"
                , method = "GET"
                , headers = []
                , body = StaticHttp.emptyBody
                }
            )
            (StaticHttp.expectString
                (\string ->
                    if String.toUpper string == string then
                        Ok string

                    else
                        Err "String was not uppercased"
                )
            )

-}
expectString : (String -> Result String value) -> Expect value
expectString =
    ExpectString


{-| Handle the incoming response as JSON and don't optimize the asset and strip out unused values.
Be sure to use the `StaticHttp.request` function if you want an optimized request that
strips out unused JSON to optimize your asset size. This function makes sense to use for things like a GraphQL request
where the JSON payload is already trimmed down to the data you explicitly requested.

If the function you pass to `expectString` yields an `Err`, then you will get at StaticHttpDecodingError that will
fail your `elm-pages` build and print out the String from the `Err`.

-}
expectUnoptimizedJson : Json.Decode.Decoder value -> Expect value
expectUnoptimizedJson =
    ExpectUnoptimizedJson


{-| This is an alternative to the other request functions in this module that doesn't perform any optimizations on the
asset. Be sure to use the optimized versions, like `StaticHttp.request`, if you can. Using those can significantly reduce
your asset sizes by removing all unused fields from your JSON.

You may want to use this function instead if you need XML data or plaintext. Or maybe you're hitting a GraphQL API,
so you don't need any additional optimization as the payload is already reduced down to exactly what you requested.

-}
unoptimizedRequest :
    Pages.Secrets.Value RequestDetails
    -> Expect a
    -> DataSource a
unoptimizedRequest requestWithSecrets expect =
    case expect of
        ExpectJson decoder ->
            Request
                ( [ requestWithSecrets ]
                , \appType rawResponseDict ->
                    case appType of
                        ApplicationType.Cli ->
                            rawResponseDict
                                |> RequestsAndPending.get (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                                |> (\maybeResponse ->
                                        case maybeResponse of
                                            Just rawResponse ->
                                                Ok
                                                    ( Dict.singleton (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash) rawResponse
                                                    , rawResponse
                                                    )

                                            Nothing ->
                                                Secrets.maskedLookup requestWithSecrets
                                                    |> requestToString
                                                    |> Pages.StaticHttpRequest.MissingHttpResponse
                                                    |> Err
                                   )
                                |> Result.andThen
                                    (\( strippedResponses, rawResponse ) ->
                                        let
                                            reduced =
                                                Json.Decode.Exploration.stripString (Internal.OptimizedDecoder.jde decoder) rawResponse
                                                    |> Result.withDefault "TODO"
                                        in
                                        rawResponse
                                            |> Json.Decode.Exploration.decodeString (decoder |> Internal.OptimizedDecoder.jde)
                                            |> (\decodeResult ->
                                                    case decodeResult of
                                                        Json.Decode.Exploration.BadJson ->
                                                            Pages.StaticHttpRequest.DecoderError "Payload sent back invalid JSON" |> Err

                                                        Json.Decode.Exploration.Errors errors ->
                                                            errors
                                                                |> Json.Decode.Exploration.errorsToString
                                                                |> Pages.StaticHttpRequest.DecoderError
                                                                |> Err

                                                        Json.Decode.Exploration.WithWarnings _ a ->
                                                            Ok a

                                                        Json.Decode.Exploration.Success a ->
                                                            Ok a
                                               )
                                            |> Result.map Done
                                            |> Result.map
                                                (\finalRequest ->
                                                    ( strippedResponses
                                                        |> Dict.insert
                                                            (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                                                            reduced
                                                    , finalRequest
                                                    )
                                                )
                                    )

                        ApplicationType.Browser ->
                            rawResponseDict
                                |> RequestsAndPending.get (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                                |> (\maybeResponse ->
                                        case maybeResponse of
                                            Just rawResponse ->
                                                Ok
                                                    ( Dict.singleton (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash) rawResponse
                                                    , rawResponse
                                                    )

                                            Nothing ->
                                                Secrets.maskedLookup requestWithSecrets
                                                    |> requestToString
                                                    |> Pages.StaticHttpRequest.MissingHttpResponse
                                                    |> Err
                                   )
                                |> Result.andThen
                                    (\( strippedResponses, rawResponse ) ->
                                        rawResponse
                                            |> Json.Decode.decodeString (decoder |> Internal.OptimizedDecoder.jd)
                                            |> (\decodeResult ->
                                                    case decodeResult of
                                                        Err _ ->
                                                            Pages.StaticHttpRequest.DecoderError "Payload sent back invalid JSON" |> Err

                                                        Ok a ->
                                                            Ok a
                                               )
                                            |> Result.map Done
                                            |> Result.map
                                                (\finalRequest ->
                                                    ( strippedResponses, finalRequest )
                                                )
                                    )
                )

        ExpectUnoptimizedJson decoder ->
            Request
                ( [ requestWithSecrets ]
                , \_ rawResponseDict ->
                    rawResponseDict
                        |> RequestsAndPending.get (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                        |> (\maybeResponse ->
                                case maybeResponse of
                                    Just rawResponse ->
                                        Ok
                                            ( Dict.singleton (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash) rawResponse
                                            , rawResponse
                                            )

                                    Nothing ->
                                        Secrets.maskedLookup requestWithSecrets
                                            |> requestToString
                                            |> Pages.StaticHttpRequest.MissingHttpResponse
                                            |> Err
                           )
                        |> Result.andThen
                            (\( strippedResponses, rawResponse ) ->
                                rawResponse
                                    |> Json.Decode.decodeString decoder
                                    |> (\decodeResult ->
                                            case decodeResult of
                                                Err error ->
                                                    error
                                                        |> Decode.errorToString
                                                        |> Pages.StaticHttpRequest.DecoderError
                                                        |> Err

                                                Ok a ->
                                                    Ok a
                                       )
                                    |> Result.map Done
                                    |> Result.map
                                        (\finalRequest ->
                                            ( strippedResponses
                                                |> Dict.insert
                                                    (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                                                    rawResponse
                                            , finalRequest
                                            )
                                        )
                            )
                )

        ExpectString mapStringFn ->
            Request
                ( [ requestWithSecrets ]
                , \_ rawResponseDict ->
                    rawResponseDict
                        |> RequestsAndPending.get (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                        |> (\maybeResponse ->
                                case maybeResponse of
                                    Just rawResponse ->
                                        Ok
                                            ( Dict.singleton (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash) rawResponse
                                            , rawResponse
                                            )

                                    Nothing ->
                                        Secrets.maskedLookup requestWithSecrets
                                            |> requestToString
                                            |> Pages.StaticHttpRequest.MissingHttpResponse
                                            |> Err
                           )
                        |> Result.andThen
                            (\( strippedResponses, rawResponse ) ->
                                rawResponse
                                    |> mapStringFn
                                    |> Result.mapError Pages.StaticHttpRequest.DecoderError
                                    |> Result.map Done
                                    |> Result.map
                                        (\finalRequest ->
                                            ( strippedResponses
                                                |> Dict.insert (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash) rawResponse
                                            , finalRequest
                                            )
                                        )
                            )
                )