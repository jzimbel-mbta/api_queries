defmodule GLConnectingRoutes do
  @moduledoc """
  Prints a JSON object or TSV table that maps all Green Line parent station IDs to the routes
  that serve their connecting stops.
  """

  alias ApiQueries.V3Api

  def get_connecting_routes do
    name_by_parent_station = get_name_by_parent_station()

    connecting_stops_by_parent_station =
      name_by_parent_station
      |> Map.keys()
      |> get_connecting_stop_ids()

    routes_by_parent_station =
      name_by_parent_station
      |> Map.keys()
      |> Task.async_stream(&get_routes_by_stop/1, ordered: false)
      |> Enum.into(%{}, fn {:ok, entry} -> entry end)

    routes_by_connecting_stop =
      connecting_stops_by_parent_station
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> Task.async_stream(&get_routes_by_stop/1, ordered: false)
      |> Enum.into(%{}, fn {:ok, entry} -> entry end)

    for {parent_station, connecting_stops} <- connecting_stops_by_parent_station, into: %{} do
      {parent_station,
       %{
         name: name_by_parent_station[parent_station],
         direct_connection_routes: routes_by_parent_station[parent_station],
         connecting_stop_routes:
           connecting_stops_to_connecting_routes(connecting_stops, routes_by_connecting_stop)
       }}
    end
  end

  def as_json(connecting_routes) do
    Jason.encode!(connecting_routes, pretty: true)
  end

  def as_tsv(connecting_routes) do
    connecting_routes
    |> Enum.map(fn {parent_station_id, info} ->
      direct_connection_route_names = Enum.map(info.direct_connection_routes, & &1.name)
      connecting_stop_route_names = Enum.map(info.connecting_stop_routes, & &1.name)

      [
        parent_station_id,
        ?\t,
        info.name,
        ?\t,
        Enum.intersperse(direct_connection_route_names, ?,),
        ?\t,
        Enum.intersperse(connecting_stop_route_names, ?,)
      ]
    end)
    |> Enum.intersperse(?\n)
    |> then(fn body ->
      ["id\tname\tdirect connection route names\tconnecting stop route names\n", body]
    end)
    |> IO.iodata_to_binary()
  end

  defp get_name_by_parent_station do
    light_rail_parent_stations =
      "stops"
      |> V3Api.fetch_resource!(%{
        "filter[route_type]" => "0",
        "include" => "parent_station",
        "fields[stop]" => "name"
      })
      |> Map.fetch!("included")
      |> Enum.into(%{}, fn parent_station ->
        {parent_station["id"], parent_station["attributes"]["name"]}
      end)

    # filter out Mattapan trolley stops
    light_rail_parent_stations
    |> Enum.filter(fn {id, _name} ->
      {_id, routes} = get_routes_by_stop(id, [0])
      Enum.any?(routes, &match?("Green-" <> _, &1.id))
    end)
    |> Enum.into(%{})
  end

  defp get_connecting_stop_ids(parent_station_ids) do
    "stops"
    |> V3Api.fetch_resource!(%{
      "filter[id]" => parent_station_ids,
      "include" => "connecting_stops"
    })
    |> Map.fetch!("data")
    |> Enum.into(%{}, fn stop_entity ->
      {
        stop_entity["id"],
        get_in(stop_entity, ["relationships", "connecting_stops", "data", Access.all(), "id"])
      }
    end)
  end

  defp get_routes_by_stop(stop_id, route_types \\ [1, 2, 3, 4]) when is_binary(stop_id) do
    "routes"
    |> V3Api.fetch_resource!(%{
      "filter[stop]" => stop_id,
      "filter[type]" => route_types,
      "fields[route]" => ~w[short_name long_name]
    })
    |> Map.fetch!("data")
    |> Enum.map(fn route_entity ->
      id = route_entity["id"]

      name =
        case {route_entity["attributes"]["short_name"], route_entity["attributes"]["long_name"]} do
          {"", long_name} -> long_name
          {short_name, _} -> short_name
        end

      %{id: id, name: name}
    end)
    |> then(fn routes -> {stop_id, routes} end)
  end

  defp connecting_stops_to_connecting_routes(connecting_stops, routes_by_connecting_stop) do
    connecting_stops
    |> Enum.flat_map(&Map.fetch!(routes_by_connecting_stop, &1))
    |> Enum.uniq()
  end
end

case System.argv() do
  ["--json"] ->
    GLConnectingRoutes.get_connecting_routes()
    |> GLConnectingRoutes.as_json()
    |> IO.puts()

  ["--tsv"] ->
    GLConnectingRoutes.get_connecting_routes()
    |> GLConnectingRoutes.as_tsv()
    |> IO.puts()

  _ ->
    IO.puts("Specify output format: either --json or --tsv")
end
