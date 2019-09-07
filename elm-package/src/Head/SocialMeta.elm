module Head.SocialMeta exposing (SummarySize(..), TwitterCard(..), rawTags, summaryLarge, summaryRegular)

import Head
import Pages.Path


{-| <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/summary>
-}
summaryRegular details =
    Summary
        { title = details.title
        , description = details.description
        , siteUser = details.siteUser
        , image = details.image
        , size = Regular
        }
        |> tags


{-| <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/summary-card-with-large-image.html>
-}
summaryLarge details =
    Summary
        { title = details.title
        , description = details.description
        , siteUser = details.siteUser
        , image = details.image
        , size = Large
        }
        |> tags


{-| <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/app-card>
-}
app :
    { title : String
    , description : Maybe String
    , siteUser : String
    , image : Maybe (Image pathKey)
    , appIdIphone : Maybe Int
    , appIdIpad : Maybe Int
    , appIdGooglePlay : Maybe String
    , appUrlIphone : Maybe String
    , appUrlIpad : Maybe String
    , appUrlGooglePlay : Maybe String
    , appCountry : Maybe String
    , appNameIphone : Maybe String
    , appNameIpad : Maybe String
    , appNameGooglePlay : Maybe String
    }
    -> List (Head.Tag pathKey)
app details =
    App details
        |> tags


ensureAtPrefix : String -> String
ensureAtPrefix twitterUsername =
    if twitterUsername |> String.startsWith "@" then
        twitterUsername

    else
        "@" ++ twitterUsername


type SummarySize
    = Regular
    | Large


type alias Image pathKey =
    { url : Pages.Path.Path pathKey Pages.Path.ToImage
    , alt : String
    }


type TwitterCard pathKey
    = Summary
        { title : String
        , description : Maybe String
        , siteUser : Maybe String
        , image : Maybe (Image pathKey)
        , size : SummarySize
        }
    | App
        { title : String
        , description : Maybe String
        , siteUser : String
        , image : Maybe (Image pathKey)
        , appIdIphone : Maybe Int
        , appIdIpad : Maybe Int
        , appIdGooglePlay : Maybe String
        , appUrlIphone : Maybe String
        , appUrlIpad : Maybe String
        , appUrlGooglePlay : Maybe String
        , appCountry : Maybe String
        , appNameIphone : Maybe String
        , appNameIpad : Maybe String
        , appNameGooglePlay : Maybe String
        }
      -- https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/player-card
    | Player
        { title : String
        , description : Maybe String
        , siteUser : String
        , image : Image pathKey
        , player : String
        , width : Int
        , height : Int
        }


rawTags : TwitterCard pathKey -> List ( String, Maybe String )
rawTags card =
    ( "twitter:card", cardValue card |> Just )
        :: (case card of
                Summary details ->
                    [ ( "twitter:title", Just details.title )
                    , ( "twitter:site", details.siteUser )
                    , ( "twitter:description", details.description )
                    , ( "twitter:image", details.image |> Maybe.map .url |> Maybe.map Pages.Path.toString )
                    , ( "twitter:image:alt", details.image |> Maybe.map .alt )
                    ]

                App details ->
                    [ ( "twitter:title", Just details.title )
                    , ( "twitter:site", Just details.siteUser )
                    , ( "twitter:description", details.description )
                    , ( "twitter:image", details.image |> Maybe.map .url |> Maybe.map Pages.Path.toString )
                    , ( "twitter:image:alt", details.image |> Maybe.map .alt )
                    , ( "twitter:app:name:iphone", details.appNameIphone )
                    , ( "twitter:app:name:ipad", details.appNameIpad )
                    , ( "twitter:app:name:googleplay", details.appNameGooglePlay )
                    , ( "twitter:app:id:iphone", details.appIdIphone |> Maybe.map String.fromInt )
                    , ( "twitter:app:id:ipad", details.appIdIpad |> Maybe.map String.fromInt )
                    , ( "twitter:app:id:googleplay", details.appIdGooglePlay )
                    , ( "twitter:app:url:iphone", details.appUrlIphone )
                    , ( "twitter:app:url:ipad", details.appUrlIpad )
                    , ( "twitter:app:url:googleplay", details.appUrlGooglePlay )
                    , ( "twitter:app:country", details.appCountry )
                    ]

                Player details ->
                    [ ( "twitter:title", Just details.title )
                    , ( "twitter:site", Just details.siteUser )
                    , ( "twitter:description", details.description )
                    , ( "twitter:image", Just (Pages.Path.toString details.image.url) )
                    , ( "twitter:image:alt", Just details.image.alt )
                    ]
           )


tags : TwitterCard pathKey -> List (Head.Tag pathKey)
tags card =
    card
        |> rawTags
        |> List.filterMap
            (\( name, maybeContent ) ->
                maybeContent
                    |> Maybe.map (\content -> Head.metaName name content)
            )


cardValue : TwitterCard pathKey -> String
cardValue card =
    case card of
        Summary details ->
            case details.size of
                Regular ->
                    "summary"

                Large ->
                    "summary_large_image"

        App details ->
            "app"

        Player details ->
            "player"
