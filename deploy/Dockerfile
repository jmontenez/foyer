FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY global.json ./
COPY server/Foyer.Api/ server/Foyer.Api/
RUN dotnet publish server/Foyer.Api -c Release -o /out --no-self-contained -p:UseAppHost=true
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /out/ ./
COPY client/build/web/ ./wwwroot/
RUN mkdir -p /data/images /home/app/.aspnet/DataProtection-Keys && chown -R app:app /data /home/app/.aspnet
USER app
ENTRYPOINT ["/app/Foyer.Api"]
