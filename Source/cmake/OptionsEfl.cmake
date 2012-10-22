SET(PROJECT_VERSION_MAJOR 0)
SET(PROJECT_VERSION_MINOR 1)
SET(PROJECT_VERSION_PATCH 0)
SET(PROJECT_VERSION ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH})

ADD_DEFINITIONS(-DBUILDING_EFL__=1)
ADD_DEFINITIONS(-DWTF_PLATFORM_EFL=1)
SET(WTF_PLATFORM_EFL 1)

FIND_PACKAGE(Cairo 1.10.2 REQUIRED)
FIND_PACKAGE(Fontconfig 2.8.0 REQUIRED)
FIND_PACKAGE(Sqlite REQUIRED)
FIND_PACKAGE(LibXml2 2.8.0 REQUIRED)
FIND_PACKAGE(LibXslt 1.1.7 REQUIRED)
FIND_PACKAGE(ICU REQUIRED)
FIND_PACKAGE(Threads REQUIRED)
FIND_PACKAGE(JPEG REQUIRED)
FIND_PACKAGE(PNG REQUIRED)
FIND_PACKAGE(ZLIB REQUIRED)

FIND_PACKAGE(GLIB 2.33.2 REQUIRED COMPONENTS gio gobject gthread)
FIND_PACKAGE(LibSoup 2.39.4.1 REQUIRED)
SET(ENABLE_GLIB_SUPPORT ON)

SET(WTF_USE_SOUP 1)
ADD_DEFINITIONS(-DWTF_USE_SOUP=1)

ADD_DEFINITIONS(-DENABLE_CONTEXT_MENUS=1)

SET(WTF_USE_PTHREADS 1)
ADD_DEFINITIONS(-DWTF_USE_PTHREADS=1)

SET(WTF_USE_ICU_UNICODE 1)
ADD_DEFINITIONS(-DWTF_USE_ICU_UNICODE=1)

SET(WTF_USE_CAIRO 1)
ADD_DEFINITIONS(-DWTF_USE_CAIRO=1)

SET(JSC_EXECUTABLE_NAME jsc)

SET(WTF_LIBRARY_NAME wtf_efl)
SET(JavaScriptCore_LIBRARY_NAME javascriptcore_efl)
SET(WebCore_LIBRARY_NAME webcore_efl)
SET(WebKit_LIBRARY_NAME ewebkit)
SET(WebKit2_LIBRARY_NAME ewebkit2)

SET(DATA_INSTALL_DIR "share/${WebKit_LIBRARY_NAME}-${PROJECT_VERSION_MAJOR}" CACHE PATH "Installation path for theme data")
SET(THEME_BINARY_DIR ${CMAKE_BINARY_DIR}/WebKit/efl/DefaultTheme)
FILE(MAKE_DIRECTORY ${THEME_BINARY_DIR})

SET(VERSION_SCRIPT "-Wl,--version-script,${CMAKE_MODULE_PATH}/eflsymbols.filter")

WEBKIT_OPTION_BEGIN()
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_ANIMATION_API ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_API_TESTS ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_BATTERY_STATUS ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_BLOB ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_CSS3_TEXT ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_CSS_IMAGE_SET ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_CSS_STICKY_POSITION ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_CSS_VARIABLES ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_CUSTOM_SCHEME_HANDLER ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_DATALIST_ELEMENT ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_DOWNLOAD_ATTRIBUTE ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_DRAG_SUPPORT ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_FAST_MOBILE_SCROLLING ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_FILTERS ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_FULLSCREEN_API ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_GAMEPAD ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_GLIB_SUPPORT ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_INPUT_TYPE_COLOR ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_LINK_PREFETCH ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_LLINT ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_MEDIA_CAPTURE ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_MEMORY_SAMPLER ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_MICRODATA ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_NAVIGATOR_CONTENT_UTILS ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_NETSCAPE_PLUGIN_API ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_NETWORK_INFO ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_PAGE_VISIBILITY_API ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_REGIONS ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_REQUEST_ANIMATION_FRAME ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_SHADOW_DOM ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_SHARED_WORKERS ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_SPELLCHECK ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_TOUCH_EVENTS ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_VIBRATION ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_VIDEO ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_VIDEO_TRACK ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_WEB_INTENTS ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_WEB_INTENTS_TAG ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_WEB_TIMING ON)
WEBKIT_OPTION_DEFAULT_PORT_VALUE(ENABLE_WORKERS ON)

# FIXME: Perhaps we need a more generic way of defining dependencies between features.
# VIDEO_TRACK depends on VIDEO.
IF (NOT ENABLE_VIDEO AND ENABLE_VIDEO_TRACK)
    MESSAGE(STATUS "Disabling VIDEO_TRACK since VIDEO support is disabled.")
    SET(ENABLE_VIDEO_TRACK OFF)
ENDIF ()
WEBKIT_OPTION_END()

OPTION(ENABLE_ECORE_X "Enable Ecore_X specific usage (cursor, bell)" ON)
IF (ENABLE_ECORE_X)
    LIST(APPEND ECORE_ADDITIONAL_COMPONENTS X)
    ADD_DEFINITIONS(-DHAVE_ECORE_X)
ENDIF ()

FIND_PACKAGE(Eina 1.7 REQUIRED)
FIND_PACKAGE(Evas 1.7 REQUIRED)
FIND_PACKAGE(Ecore 1.7 COMPONENTS Evas File Input ${ECORE_ADDITIONAL_COMPONENTS})
FIND_PACKAGE(Edje 1.7 REQUIRED)
FIND_PACKAGE(Eet 1.7 REQUIRED)
FIND_PACKAGE(Eeze 1.7 REQUIRED)
FIND_PACKAGE(Efreet 1.7 REQUIRED)
FIND_PACKAGE(E_DBus 1.7 COMPONENTS EUKit)

# Elementary is needed to build MiniBrowser
FIND_PACKAGE(Elementary 1.7)

FIND_PACKAGE(Freetype 2.4.2 REQUIRED)
FIND_PACKAGE(HarfBuzz 0.9.2 REQUIRED)
SET(WTF_USE_FREETYPE 1)
SET(WTF_USE_HARFBUZZ_NG 1)
ADD_DEFINITIONS(-DWTF_USE_FREETYPE=1)
ADD_DEFINITIONS(-DWTF_USE_HARFBUZZ_NG=1)

IF (ENABLE_WEBKIT2 AND ENABLE_NETSCAPE_PLUGIN_API)
    SET(ENABLE_PLUGIN_PROCESS 1)
ENDIF ()

IF (NOT ENABLE_SVG)
  SET(ENABLE_SVG_FONTS 0)
ENDIF ()

IF (ENABLE_BATTERY_STATUS)
    FIND_PACKAGE(DBus REQUIRED)
ENDIF ()

IF (ENABLE_VIDEO OR ENABLE_WEB_AUDIO)
    SET(GSTREAMER_COMPONENTS app interfaces pbutils)
    SET(WTF_USE_GSTREAMER 1)
    ADD_DEFINITIONS(-DWTF_USE_GSTREAMER=1)

    IF (ENABLE_VIDEO)
        LIST(APPEND GSTREAMER_COMPONENTS video)
    ENDIF()

    IF (ENABLE_WEB_AUDIO)
        LIST(APPEND GSTREAMER_COMPONENTS audio fft)
        ADD_DEFINITIONS(-DWTF_USE_WEBAUDIO_GSTREAMER=1)
    ENDIF ()

    FIND_PACKAGE(GStreamer REQUIRED COMPONENTS ${GSTREAMER_COMPONENTS})
ENDIF ()

IF (ENABLE_WEBGL)
  FIND_PACKAGE(OpenGL REQUIRED)
ENDIF ()

IF (ENABLE_INSPECTOR)
    SET(WEB_INSPECTOR_DIR "${DATA_INSTALL_DIR}/inspector")
    ADD_DEFINITIONS(-DWEB_INSPECTOR_DIR=\"${CMAKE_BINARY_DIR}/${WEB_INSPECTOR_DIR}\")
    ADD_DEFINITIONS(-DWEB_INSPECTOR_INSTALL_DIR=\"${CMAKE_INSTALL_PREFIX}/${WEB_INSPECTOR_DIR}\")
ENDIF ()

SET(CPACK_SOURCE_GENERATOR TBZ2)

IF (WTF_USE_TILED_BACKING_STORE)
  SET(WTF_USE_ACCELERATED_COMPOSITING 1)
  ADD_DEFINITIONS(-DWTF_USE_ACCELERATED_COMPOSITING=1)

  SET(WTF_USE_COORDINATED_GRAPHICS 1)
  ADD_DEFINITIONS(-DWTF_USE_COORDINATED_GRAPHICS=1)

  SET(WTF_USE_TEXTURE_MAPPER 1)
  ADD_DEFINITIONS(-DWTF_USE_TEXTURE_MAPPER=1)

  SET(WTF_USE_TEXTURE_MAPPER_GL 1)
  ADD_DEFINITIONS(-DWTF_USE_TEXTURE_MAPPER_GL=1)

  SET(WTF_USE_3D_GRAPHICS 1)
  ADD_DEFINITIONS(-DWTF_USE_3D_GRAPHICS=1)

  FIND_PACKAGE(OpenGL REQUIRED)
ENDIF()

IF (ENABLE_SPELLCHECK)
      FIND_PACKAGE(Enchant REQUIRED)
      ADD_DEFINITIONS(-DENABLE_SPELLCHECK=1)
ENDIF()
