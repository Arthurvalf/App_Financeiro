# Finança — app Android com o José Pinto

App pessoal de finanças em Flutter:

- **Login por e-mail e senha** (Firebase Authentication). Cada pessoa tem sua conta e seus dados.
- **Captura automática do Nubank**: lê as notificações do Nubank (compras, Pix) e cria o lançamento sozinho, já categorizado, com aviso na hora.
- **José Pinto** (Google Gemini): conversa sobre seus números reais, prevê o fechamento do mês, detecta assinaturas,
  recomenda investimentos com nota e risco, pesquisa taxas atuais no Google, **lembra do que você conta** e executa ações
  (anotar gastos, criar metas, dívidas, categorias e regras).
- **Posso comprar isso?**: veredito do José com o impacto no mês, nas metas e nas parcelas futuras.
- **Planos**: metas por categoria, **dívidas e parcelas** (cada parcela entra no mês dela) e **simulador "e se"**
  com Selic/CDI/IPCA reais do Banco Central.
- **Calendário de gastos** (mapa de calor do mês).
- **Categorias próprias e regras automáticas** ("contém posto → Transporte").
- **Widget na tela inicial** e **notificações**: gasto capturado, metas em 80%/100%, parcela vencendo, resumo semanal e dia do salário.

## Como o APK é gerado

Todo `push` na pasta `mobile/` dispara o GitHub Actions (`.github/workflows/build.yml`), que:

1. compila e testa o app;
2. publica o APK em **Releases** (`financa-beta.apk`);
3. publica uma versão web na branch `gh-pages` (para testar no navegador);
4. salva os logs do build na branch `ci-logs`.

## Instalar no celular

1. Abra a página **Releases** do repositório no celular e baixe `financa-beta.apk`.
2. Permita "instalar apps desconhecidos" para o navegador quando o Android pedir.
3. Abra o app, crie a conta e cole a chave do Gemini em **Perfil**.

## Ativar a captura do Nubank

1. Em **Perfil → Captura automática do Nubank**, toque em **Ativar acesso às notificações** e ligue "Finança".
2. Android 13 ou mais novo: se aparecer "configuração restrita", toque em **Liberar configurações restritas**,
   abra o menu **⋮** e escolha **Permitir configurações restritas**. Volte e ative de novo.
3. No app do Nubank, mantenha as notificações de compras e Pix ligadas.
4. Recomendado: tire o Finança da economia de bateria.

Use **Simular compra** para testar sem gastar nada, e **Ver capturas** para ver o que chegou do Nubank.

## Testar sem instalar

- **Navegador**: em *Settings → Pages* do repositório, escolha a branch `gh-pages` e salve. O app abre em
  `https://arthurvalf.github.io/App_Financeiro/`. Tudo funciona, menos a captura do Nubank (que precisa do Android).
- **Emulador online**: envie o APK em [appetize.io](https://appetize.io) para rodar um Android no navegador.

## Configuração do Firebase

- Authentication → Sign-in method → **E-mail/senha** ativado.
- Firestore Database criado. Em **Regras**, cole o conteúdo de [`firestore.rules`](firestore.rules) e publique.
- A configuração pública do projeto está em `lib/config.dart`.

## Chave do Gemini (embutida no APK)

1. No GitHub: **Settings → Secrets and variables → Actions → New repository secret**.
2. Nome: `GEMINI_API_KEY`. Valor: sua chave do [aistudio.google.com](https://aistudio.google.com).
3. Rode o build de novo (qualquer push em `mobile/` ou *Actions → Build APK + Web → Run workflow*).

O build embaralha a chave e a injeta só no APK (a versão web pública não recebe a chave; lá dá para colar uma no Perfil).
Ela nunca fica no código nem nos logs. Observação honesta: qualquer chave dentro de um app pode ser extraída por alguém
determinado; o embaralhamento só impede que ela seja achada facilmente. Para um app pessoal o risco é baixo (no máximo,
alguém gastar sua cota gratuita) e você pode trocar a chave quando quiser.

## Estrutura

```
lib/
  main.dart                app e rotas
  config.dart              Firebase público + modelos do Gemini
  theme.dart               visual (claro, pílulas, verde-limão)
  models.dart              categorias, lançamentos, investimentos, perfil
  services/
    auth_service.dart      login (Firebase Auth REST)
    firestore.dart         banco de dados (Firestore REST)
    gemini.dart            cliente do Gemini
    jose.dart              persona, contexto financeiro e ações do José Pinto
    capture.dart           ponte com o Android + leitor das notificações do Nubank
    categorizer.dart       categorias por palavra-chave
  state/app_state.dart     estado, sincronização, alertas
  screens/                 telas
android/app/src/main/kotlin/com/arthurvalf/financa/
  CaptureService.kt        escuta as notificações do Nubank
  MainActivity.kt          canal com o Flutter
```
