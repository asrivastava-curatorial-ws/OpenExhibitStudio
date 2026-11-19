# Earth in longitude

Open project.oes.json in Studio and choose **Test exhibit**, or open it in the standalone Player.

In Hardware inject encoder = 45. The Mapping preview (Exhibit content) shifts longitude by 45°. Input is an absolute angle in degrees; the supplied encoder sketch reports one degree per accepted tick.

**Installation.** Four projectors around a matte sphere. Projector distance, aim and throw must be measured. Example radius 2 m.

Use the Uno sketch with encoder A on D3, B on D4 and common ground. Four equatorial projectors leave polar caps outside their illumination. The coverage tool quantifies the gaps from the configured geometry.

Coastline texture from public-domain Natural Earth data, processed by QGIS. No political boundary overlay. https://www.naturalearthdata.com/about/terms-of-use/
