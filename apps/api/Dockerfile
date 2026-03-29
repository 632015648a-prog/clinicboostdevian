FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copiar csproj y restaurar dependencias (capa cacheada)
COPY apps/api/ClinicBoost.Api.csproj ./apps/api/
RUN dotnet restore apps/api/ClinicBoost.Api.csproj

# Copiar el resto del código y compilar
COPY apps/api/ ./apps/api/
WORKDIR /src/apps/api
RUN dotnet publish -c Release -o /app/publish --no-restore

# Runtime image
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

# No ejecutar como root
RUN adduser --disabled-password --gecos "" appuser
USER appuser

EXPOSE 5000
ENV ASPNETCORE_URLS=http://+:5000
ENTRYPOINT ["dotnet", "ClinicBoost.Api.dll"]
