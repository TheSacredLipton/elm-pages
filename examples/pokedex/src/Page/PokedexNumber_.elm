module Page.PokedexNumber_ exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import DataSource.Http
import Head
import Head.Seo as Seo
import Html exposing (..)
import Html.Attributes exposing (src)
import OptimizedDecoder as Decode
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Secrets
import Shared
import View exposing (View)


type alias Model =
    ()


type alias Msg =
    Never


type alias RouteParams =
    { pokedexnumber : String }


page : Page RouteParams Data
page =
    Page.prerenderedRouteWithFallback
        { head = head
        , routes = routes
        , data = data
        , handleFallback =
            \{ pokedexnumber } ->
                let
                    asNumber : Int
                    asNumber =
                        String.toInt pokedexnumber |> Maybe.withDefault -1
                in
                DataSource.succeed
                    (asNumber > 0 && asNumber < 150)
        }
        |> Page.buildNoState { view = view }


routes : DataSource (List RouteParams)
routes =
    DataSource.succeed []


data : RouteParams -> DataSource Data
data routeParams =
    DataSource.Http.get (Secrets.succeed ("https://pokeapi.co/api/v2/pokemon/" ++ routeParams.pokedexnumber))
        (Decode.map2 Data
            (Decode.field "forms" (Decode.index 0 (Decode.field "name" Decode.string)))
            (Decode.field "types" (Decode.list (Decode.field "type" (Decode.field "name" Decode.string))))
        )


head :
    StaticPayload Data RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


type alias Data =
    { name : String
    , abilities : List String
    }


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { title = static.data.name
    , body =
        [ h1 []
            [ text static.data.name
            ]
        , text (static.data.abilities |> String.join ", ")
        , img
            [ src <| "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/" ++ static.routeParams.pokedexnumber ++ ".png"
            ]
            []
        ]
    }