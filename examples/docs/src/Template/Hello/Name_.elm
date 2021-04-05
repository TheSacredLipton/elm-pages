module Template.Hello.Name_ exposing (Model, Msg, template)

import Element exposing (Element)
import Element.Region
import Head
import Head.Seo as Seo
import Pages exposing (images)
import Pages.PagePath exposing (PagePath)
import Shared
import Site
import Template exposing (StaticPayload, Template, TemplateWithState)


type alias Model =
    ()


type alias Msg =
    Never


type alias Route =
    { name : String
    }


template : Template Route ()
template =
    Template.noStaticData { head = head }
        |> Template.buildNoState { view = view }


head :
    StaticPayload ()
    -> List (Head.Tag Pages.PathKey)
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = images.iconPng
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = Site.tagline
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


type alias StaticData =
    ()


view :
    StaticPayload StaticData
    -> Shared.PageView msg
view static =
    { title = "TODO title"
    , body = []
    }