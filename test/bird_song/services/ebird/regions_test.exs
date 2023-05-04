defmodule BirdSong.Services.Ebird.RegionsTest do
  use BirdSong.SupervisedCase, async: true

  alias BirdSong.{
    Services.Ebird,
    Services.Ebird.Regions,
    Services.Ebird.Regions.Region,
    Services.Worker
  }

  @moduletag throttle_ms: 3_000
  @moduletag service: :Ebird

  @tag :tmp_dir
  test "&get_countries/1", tags do
    %{
      worker: worker,
      bypass: bypass
    } = get_worker_setup(Ebird, :Regions, tags)

    Bypass.expect(bypass, &__MODULE__.success_response/1)
    assert {:ok, regions} = Regions.get_countries(worker)

    assert regions === [
             %Region{name: "Afghanistan", code: "AF", level: :country},
             %Region{name: "Albania", code: "AL", level: :country},
             %Region{name: "Algeria", code: "DZ", level: :country},
             %Region{name: "American Samoa", code: "AS", level: :country}
           ]
  end

  @tag use_bypass?: false
  @tag tmp_dir: false
  test "&get_subregions/3", tags do
    assert %{
             worker: worker
           } = get_worker_setup(Ebird, :Regions, tags)

    assert Worker.full_data_folder_path(worker) === {:ok, "data/regions/ebird"}

    assert {:ok, [_ | _] = countries} = Regions.get_countries(worker)
    countries_len = length(countries)

    has_sub1_pct = MapSet.size(has_sub1()) / countries_len
    no_sub1_pct = MapSet.size(no_sub1()) / countries_len
    has_sub2_pct = MapSet.size(has_sub2()) / countries_len
    no_sub2_pct = MapSet.size(no_sub2()) / countries_len

    assert Float.round(has_sub1_pct * 100, 1) === 79.1
    assert Float.round(no_sub1_pct, 1) * 100 === 20.0
    assert Float.round(has_sub2_pct, 1) * 100 === 10.0
    assert Float.round(no_sub2_pct, 1) * 100 === 90.0

    for country <- countries do
      assert %Region{name: country_name, code: country_code} = country
      record = country_code <> " " <> country_name

      sub1_response = Regions.get_subregions(country, worker, :subnational1)

      case MapSet.member?(has_sub1(), record) do
        true ->
          refute MapSet.member?(no_sub1(), record),
                 "expected #{inspect(record)} NOT to be in no_sub1()"

          assert {:ok, [%Region{} | _]} = sub1_response

        false ->
          assert MapSet.member?(no_sub1(), record),
                 "expected #{inspect(record)} to be in no_sub1()"

          assert sub1_response ===
                   {:error, {:no_subregions, level: :subnational1, parent: country_code}}
      end

      sub2_response = Regions.get_subregions(country, worker, :subnational2)

      case MapSet.member?(has_sub2(), record) do
        true ->
          refute MapSet.member?(no_sub2(), record),
                 "expected #{inspect(record)} NOT to be in no_sub2()"

          assert {:ok, [%Region{} | _] = sub1} = sub1_response
          assert {:ok, [%Region{} | _] = sub2} = sub2_response
          refute sub1 === sub2

        false ->
          assert MapSet.member?(no_sub2(), record),
                 "expected #{inspect(record)} to be in no_sub2()"

          assert sub2_response ===
                   {:error, {:no_subregions, level: :subnational2, parent: country.code}}
      end
    end
  end

  def success_response(
        %Plug.Conn{path_info: ["v2", "ref", "region", "list", level, _country]} = conn
      )
      when level in ["country", "subnational1", "subnational2"] do
    Plug.Conn.resp(
      conn,
      200,
      ~s([
      { "code": "AF", "name": "Afghanistan" },
      { "code": "AL", "name": "Albania" },
      { "code": "DZ", "name": "Algeria" },
      { "code": "AS", "name": "American Samoa" }
      ])
    )
  end

  def has_sub1() do
    MapSet.new([
      "ZW Zimbabwe",
      "ZM Zambia",
      "YE Yemen",
      "VI Virgin Islands (U.S.)",
      "VN Vietnam",
      "VE Venezuela",
      "VU Vanuatu",
      "UZ Uzbekistan",
      "UY Uruguay",
      "UM United States Minor Outlying Islands",
      "US United States",
      "GB United Kingdom",
      "AE United Arab Emirates",
      "UA Ukraine",
      "UG Uganda",
      "TV Tuvalu",
      "TM Turkmenistan",
      "TR Türkiye",
      "TN Tunisia",
      "TT Trinidad and Tobago",
      "TO Tonga",
      "TG Togo",
      "TL Timor-Leste",
      "TH Thailand",
      "TZ Tanzania",
      "TJ Tajikistan",
      "TW Taiwan",
      "SY Syria",
      "CH Switzerland",
      "SE Sweden",
      "SR Suriname",
      "SD Sudan",
      "LK Sri Lanka",
      "ES Spain",
      "SS South Sudan",
      "KR South Korea",
      "ZA South Africa",
      "SO Somalia",
      "SB Solomon Islands",
      "SI Slovenia",
      "SK Slovakia",
      "SL Sierra Leone",
      "SC Seychelles",
      "RS Serbia",
      "SN Senegal",
      "SA Saudi Arabia",
      "ST São Tomé and Príncipe",
      "SM San Marino",
      "WS Samoa",
      "VC Saint Vincent and the Grenadines",
      "LC Saint Lucia",
      "KN Saint Kitts and Nevis",
      "SH Saint Helena, Ascension, and Tristan da Cunha",
      "RW Rwanda",
      "RU Russia",
      "RO Romania",
      "QA Qatar",
      "PR Puerto Rico",
      "PT Portugal",
      "PL Poland",
      "PH Philippines",
      "PE Peru",
      "PY Paraguay",
      "PG Papua New Guinea",
      "PA Panama",
      "PW Palau",
      "PK Pakistan",
      "OM Oman",
      "NO Norway",
      "MK North Macedonia",
      "KP North Korea",
      "MP Northern Mariana Islands",
      "NG Nigeria",
      "NE Niger",
      "NI Nicaragua",
      "NZ New Zealand",
      "NL Netherlands",
      "NP Nepal",
      "NR Nauru",
      "NA Namibia",
      "MM Myanmar",
      "MZ Mozambique",
      "MA Morocco",
      "ME Montenegro",
      "MN Mongolia",
      "MD Moldova",
      "FM Micronesia",
      "MX Mexico",
      "MU Mauritius",
      "MR Mauritania",
      "MH Marshall Islands",
      "MT Malta",
      "ML Mali",
      "MV Maldives",
      "MY Malaysia",
      "MW Malawi",
      "MG Madagascar",
      "LU Luxembourg",
      "LT Lithuania",
      "LI Liechtenstein",
      "LY Libya",
      "LR Liberia",
      "LS Lesotho",
      "LB Lebanon",
      "LV Latvia",
      "LA Laos",
      "KG Kyrgyzstan",
      "KW Kuwait",
      "KI Kiribati",
      "KE Kenya",
      "KZ Kazakhstan",
      "JO Jordan",
      "JP Japan",
      "JM Jamaica",
      "IT Italy",
      "IL Israel",
      "IE Ireland",
      "IQ Iraq",
      "IR Iran",
      "ID Indonesia",
      "IN India",
      "IS Iceland",
      "HU Hungary",
      "HN Honduras",
      "HT Haiti",
      "GY Guyana",
      "GW Guinea-Bissau",
      "GN Guinea",
      "GT Guatemala",
      "GD Grenada",
      "GR Greece",
      "GH Ghana",
      "DE Germany",
      "GE Georgia",
      "GM Gambia",
      "GA Gabon",
      "PF French Polynesia",
      "FR France",
      "FI Finland",
      "FJ Fiji",
      "ET Ethiopia",
      "SZ Eswatini",
      "EE Estonia",
      "ER Eritrea",
      "GQ Equatorial Guinea",
      "SV El Salvador",
      "EG Egypt",
      "EC Ecuador",
      "CD DR Congo",
      "DO Dominican Republic",
      "DM Dominica",
      "DJ Djibouti",
      "DK Denmark",
      "CZ Czech Republic",
      "CY Cyprus",
      "CU Cuba",
      "HR Croatia",
      "CI Côte d'Ivoire",
      "CR Costa Rica",
      "CG Congo",
      "KM Comoros",
      "CO Colombia",
      "CN China",
      "CL Chile",
      "TD Chad",
      "CF Central African Republic",
      "KY Cayman Islands",
      "BQ Caribbean Netherlands",
      "CV Cape Verde",
      "CA Canada",
      "CM Cameroon",
      "KH Cambodia",
      "BI Burundi",
      "BF Burkina Faso",
      "BG Bulgaria",
      "BN Brunei",
      "BR Brazil",
      "BW Botswana",
      "BA Bosnia and Herzegovina",
      "BO Bolivia",
      "BT Bhutan",
      "BJ Benin",
      "BZ Belize",
      "BE Belgium",
      "BY Belarus",
      "BB Barbados",
      "BD Bangladesh",
      "BH Bahrain",
      "BS Bahamas",
      "AZ Azerbaijan",
      "AT Austria",
      "AU Australia",
      "AM Armenia",
      "AR Argentina",
      "AG Antigua and Barbuda",
      "AO Angola",
      "AD Andorra",
      "DZ Algeria",
      "AL Albania",
      "AF Afghanistan"
    ])
  end

  defp no_sub1() do
    MapSet.new([
      "EH Western Sahara",
      "WF Wallis and Futuna",
      "VG Virgin Islands (British)",
      "VA Vatican City (Holy See)",
      "TC Turks and Caicos Islands",
      "TK Tokelau",
      "SJ Svalbard",
      "GS South Georgia and South Sandwich Islands",
      "SX Sint Maarten",
      "SG Singapore",
      "PM Saint Pierre and Miquelon",
      "MF Saint Martin (French part)",
      "BL Saint Barthélemy",
      "RE Réunion",
      "PN Pitcairn Islands",
      "PS Palestinian Territory",
      "NF Norfolk Island",
      "NU Niue",
      "NC New Caledonia",
      "MS Montserrat",
      "MC Monaco",
      "YT Mayotte",
      "MQ Martinique",
      "MO Macau",
      "XK Kosovo",
      "JE Jersey",
      "IM Isle of Man",
      "HK Hong Kong",
      "XX High Seas",
      "HM Heard Island and McDonald Islands",
      "GG Guernsey",
      "GU Guam",
      "GP Guadeloupe",
      "GL Greenland",
      "GI Gibraltar",
      "TF French Southern and Antarctic Lands",
      "GF French Guiana",
      "FO Faroe Islands",
      "FK Falkland Islands (Malvinas)",
      "CW Curaçao",
      "CS Coral Sea Islands",
      "CK Cook Islands",
      "CC Cocos (Keeling) Islands",
      "CP Clipperton Island",
      "CX Christmas Island",
      "IO British Indian Ocean Territory",
      "BV Bouvet Island",
      "BM Bermuda",
      "AC Ashmore and Cartier Islands",
      "AW Aruba",
      "AQ Antarctica",
      "AI Anguilla",
      "AS American Samoa"
    ])
  end

  defp has_sub2() do
    MapSet.new([
      "US United States",
      "GB United Kingdom",
      "LK Sri Lanka",
      "ES Spain",
      "PT Portugal",
      "NZ New Zealand",
      "NP Nepal",
      "MX Mexico",
      "JP Japan",
      "IE Ireland",
      "ID Indonesia",
      "IN India",
      "GR Greece",
      "DE Germany",
      "FR France",
      "GQ Equatorial Guinea",
      "CL Chile",
      "CA Canada",
      "AU Australia",
      "AR Argentina"
    ])
  end

  defp no_sub2() do
    no_sub1()
    |> Enum.concat([
      "ZW Zimbabwe",
      "ZM Zambia",
      "YE Yemen",
      "WF Wallis and Futuna",
      "VI Virgin Islands (U.S.)",
      "VN Vietnam",
      "VE Venezuela",
      "VU Vanuatu",
      "UZ Uzbekistan",
      "UY Uruguay",
      "UM United States Minor Outlying Islands",
      "AE United Arab Emirates",
      "UA Ukraine",
      "UG Uganda",
      "TV Tuvalu",
      "TM Turkmenistan",
      "TR Türkiye",
      "TN Tunisia",
      "TT Trinidad and Tobago",
      "TO Tonga",
      "TG Togo",
      "TL Timor-Leste",
      "TH Thailand",
      "TZ Tanzania",
      "TJ Tajikistan",
      "TW Taiwan",
      "SY Syria",
      "CH Switzerland",
      "SE Sweden",
      "SR Suriname",
      "SD Sudan",
      "SS South Sudan",
      "KR South Korea",
      "ZA South Africa",
      "SO Somalia",
      "SB Solomon Islands",
      "SI Slovenia",
      "SK Slovakia",
      "SL Sierra Leone",
      "SC Seychelles",
      "RS Serbia",
      "SN Senegal",
      "SA Saudi Arabia",
      "ST São Tomé and Príncipe",
      "SM San Marino",
      "WS Samoa",
      "VC Saint Vincent and the Grenadines",
      "LC Saint Lucia",
      "KN Saint Kitts and Nevis",
      "SH Saint Helena, Ascension, and Tristan da Cunha",
      "RW Rwanda",
      "RU Russia",
      "RO Romania",
      "QA Qatar",
      "PR Puerto Rico",
      "PL Poland",
      "PH Philippines",
      "PE Peru",
      "PY Paraguay",
      "PG Papua New Guinea",
      "PA Panama",
      "PW Palau",
      "PK Pakistan",
      "OM Oman",
      "NO Norway",
      "MK North Macedonia",
      "KP North Korea",
      "MP Northern Mariana Islands",
      "NG Nigeria",
      "NE Niger",
      "NI Nicaragua",
      "NL Netherlands",
      "NR Nauru",
      "NA Namibia",
      "MM Myanmar",
      "MZ Mozambique",
      "MA Morocco",
      "ME Montenegro",
      "MN Mongolia",
      "MD Moldova",
      "FM Micronesia",
      "MU Mauritius",
      "MR Mauritania",
      "MH Marshall Islands",
      "MT Malta",
      "ML Mali",
      "MV Maldives",
      "MY Malaysia",
      "MW Malawi",
      "MG Madagascar",
      "LU Luxembourg",
      "LT Lithuania",
      "LI Liechtenstein",
      "LY Libya",
      "LR Liberia",
      "LS Lesotho",
      "LB Lebanon",
      "LV Latvia",
      "LA Laos",
      "KG Kyrgyzstan",
      "KW Kuwait",
      "KI Kiribati",
      "KE Kenya",
      "KZ Kazakhstan",
      "JO Jordan",
      "JM Jamaica",
      "IT Italy",
      "IL Israel",
      "IQ Iraq",
      "IR Iran",
      "IS Iceland",
      "HU Hungary",
      "HN Honduras",
      "HT Haiti",
      "GY Guyana",
      "GW Guinea-Bissau",
      "GN Guinea",
      "GT Guatemala",
      "GD Grenada",
      "GH Ghana",
      "GE Georgia",
      "GM Gambia",
      "GA Gabon",
      "PF French Polynesia",
      "FI Finland",
      "FJ Fiji",
      "ET Ethiopia",
      "SZ Eswatini",
      "EE Estonia",
      "ER Eritrea",
      "SV El Salvador",
      "EG Egypt",
      "EC Ecuador",
      "CD DR Congo",
      "DO Dominican Republic",
      "DM Dominica",
      "DJ Djibouti",
      "DK Denmark",
      "CZ Czech Republic",
      "CY Cyprus",
      "CU Cuba",
      "HR Croatia",
      "CI Côte d'Ivoire",
      "CR Costa Rica",
      "CG Congo",
      "KM Comoros",
      "CO Colombia",
      "CP Clipperton Island",
      "CN China",
      "TD Chad",
      "CF Central African Republic",
      "KY Cayman Islands",
      "BQ Caribbean Netherlands",
      "CV Cape Verde",
      "CM Cameroon",
      "KH Cambodia",
      "BI Burundi",
      "BF Burkina Faso",
      "BG Bulgaria",
      "BN Brunei",
      "BR Brazil",
      "BW Botswana",
      "BA Bosnia and Herzegovina",
      "BO Bolivia",
      "BT Bhutan",
      "BM Bermuda",
      "BJ Benin",
      "BZ Belize",
      "BE Belgium",
      "BY Belarus",
      "BB Barbados",
      "BD Bangladesh",
      "BH Bahrain",
      "BS Bahamas",
      "AZ Azerbaijan",
      "AT Austria",
      "AM Armenia",
      "AG Antigua and Barbuda",
      "AO Angola",
      "AD Andorra",
      "DZ Algeria",
      "AL Albania",
      "AF Afghanistan"
    ])
    |> MapSet.new()
  end
end
