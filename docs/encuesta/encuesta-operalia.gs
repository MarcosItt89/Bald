/**
 * Encuesta de diseño de interfaz — Operalia
 * Materia: Diseño y evaluación de interfaces
 * Alumno: Ramírez Guerra Marcos Yeran · No. de control 23210648
 *
 * Cómo usarlo:
 *   1. Abre https://script.google.com → "Nuevo proyecto".
 *   2. Borra el contenido de Código.gs y pega TODO este archivo.
 *   3. Guarda (Ctrl+S), elige la función crearEncuesta y pulsa "Ejecutar".
 *   4. Autoriza los permisos (Formularios y conexión a servicios externos).
 *   5. Abre "Registro de ejecución": ahí aparecen el enlace público y el de edición.
 *
 * Las imágenes se descargan de GitHub (repositorio público MarcosItt89/Bald)
 * y quedan guardadas dentro del formulario, así que no dependen del repo después.
 */

const IMG_BASE = 'https://raw.githubusercontent.com/MarcosItt89/Bald/claude/project-thread-s5rcwb/docs/encuesta/img/';

const LIKERT = ['Muy en desacuerdo', 'En desacuerdo', 'Neutral', 'De acuerdo', 'Muy de acuerdo'];

// Pantallas que se evalúan una por una.
const PANTALLAS = [
  {
    archivo: '01-login.png',
    titulo: 'Pantalla 1 · Inicio de sesión',
    descripcion: 'Es lo primero que ve el usuario: presentación de Operalia a la izquierda y el formulario de acceso a la derecha.',
  },
  {
    archivo: '02-dashboard.png',
    titulo: 'Pantalla 2 · Dashboard (panel principal)',
    descripcion: 'Resumen del día del gerente: tarjetas con indicadores, checklists de hoy y tareas asignadas. El menú lateral agrupa los módulos.',
  },
  {
    archivo: '03-inventario.png',
    titulo: 'Pantalla 3 · Inventario',
    descripcion: 'Tabla de productos con búsqueda, filtros, existencias y estado (Normal, Bajo stock, Crítico, Sin existencia).',
  },
  {
    archivo: '04-checklists.png',
    titulo: 'Pantalla 4 · Checklists del día',
    descripcion: 'Listas de revisión operativas (apertura, limpieza, temperaturas…) con barra de cumplimiento, pestañas por estado y botón para iniciar.',
  },
  {
    archivo: '05-tareas.png',
    titulo: 'Pantalla 5 · Tareas',
    descripcion: 'Tareas asignadas al personal con prioridad, fecha límite, estado y acciones rápidas (Iniciar, Completar, Foto).',
  },
];

const ASPECTOS = [
  'La información está organizada de forma clara',
  'Los colores y el estilo visual son agradables',
  'El texto se lee con facilidad (tamaño y contraste)',
  'Entiendo para qué sirve cada botón o icono',
  'Encontraría rápido lo que necesito en esta pantalla',
];

// System Usability Scale (SUS), versión en español.
const SUS = [
  'Creo que me gustaría usar este sistema con frecuencia',
  'El sistema me parece innecesariamente complejo',
  'El sistema me parece fácil de usar',
  'Creo que necesitaría ayuda de una persona con conocimientos técnicos para usarlo',
  'Las diferentes funciones del sistema están bien integradas',
  'Hay demasiadas inconsistencias en el sistema',
  'Creo que la mayoría de las personas aprenderían a usarlo muy rápido',
  'El sistema me parece muy difícil de manejar',
  'Me sentiría seguro(a) usando el sistema',
  'Necesitaría aprender muchas cosas antes de poder usarlo',
];

function imagen(nombre) {
  const resp = UrlFetchApp.fetch(IMG_BASE + nombre, { muteHttpExceptions: true });
  if (resp.getResponseCode() !== 200) {
    Logger.log('⚠ No se pudo descargar ' + nombre + ' (HTTP ' + resp.getResponseCode() + '). Agrégala a mano.');
    return null;
  }
  return resp.getBlob().setName(nombre);
}

function agregarImagen(form, nombre, titulo, ayuda) {
  const blob = imagen(nombre);
  if (!blob) return;
  const item = form.addImageItem().setImage(blob).setTitle(titulo).setAlignment(FormApp.Alignment.CENTER);
  if (ayuda) item.setHelpText(ayuda);
}

function crearEncuesta() {
  const form = FormApp.create('Encuesta de diseño de interfaz — Operalia');
  form.setDescription(
    'Operalia es una aplicación web para administrar la operación diaria de supermercados con varias sucursales: ' +
    'inventario, recibo de mercancía, checklists, tareas, precios y más.\n\n' +
    'Esta encuesta evalúa únicamente el DISEÑO DE LA INTERFAZ. Verás capturas de las pantallas principales; ' +
    'no necesitas haber usado la aplicación. Toma de 5 a 7 minutos y es anónima.\n\n' +
    'Proyecto escolar de Diseño y evaluación de interfaces — Ramírez Guerra Marcos Yeran (23210648).'
  );
  form.setCollectEmail(false);
  form.setLimitOneResponsePerUser(false);
  form.setProgressBar(true);
  form.setShowLinkToRespondAgain(false);
  form.setConfirmationMessage('¡Gracias! Tus respuestas ayudarán a mejorar el diseño de Operalia.');

  // ── Sección 1: perfil del participante ────────────────────────────────────
  form.addSectionHeaderItem().setTitle('Sobre ti');
  form.addMultipleChoiceItem().setTitle('¿Cuál es tu edad?').setRequired(true)
    .setChoiceValues(['Menos de 18', '18 a 24', '25 a 34', '35 a 44', '45 o más']);
  form.addMultipleChoiceItem().setTitle('¿Cuál describe mejor tu relación con un supermercado o tienda?').setRequired(true)
    .setChoiceValues(['Trabajo en piso de venta / cajas / almacén', 'Soy encargado, jefe o gerente', 'Soy estudiante', 'Solo soy cliente'])
    .showOtherOption(true);
  form.addScaleItem().setTitle('¿Qué tan cómodo(a) te sientes usando aplicaciones web o de celular?')
    .setBounds(1, 5).setLabels('Nada cómodo', 'Muy cómodo').setRequired(true);
  form.addMultipleChoiceItem().setTitle('¿En qué dispositivo estás contestando?').setRequired(true)
    .setChoiceValues(['Celular', 'Computadora', 'Tableta']);

  // ── Secciones 2-6: una por pantalla ──────────────────────────────────────
  PANTALLAS.forEach((p) => {
    form.addPageBreakItem().setTitle(p.titulo).setHelpText(p.descripcion);
    agregarImagen(form, p.archivo, p.titulo);
    form.addGridItem().setTitle('Evalúa esta pantalla')
      .setRows(ASPECTOS).setColumns(LIKERT).setRequired(true);
    form.addScaleItem().setTitle('Calificación general de esta pantalla')
      .setBounds(1, 5).setLabels('Muy mala', 'Excelente').setRequired(true);
    form.addParagraphTextItem().setTitle('¿Qué cambiarías o qué te confundió en esta pantalla? (opcional)');
  });

  // ── Sección 7: versión de celular ────────────────────────────────────────
  form.addPageBreakItem().setTitle('Versión para celular')
    .setHelpText('Operalia se adapta al celular: el menú se oculta y las tablas se convierten en tarjetas.');
  agregarImagen(form, '02-dashboard-movil.png', 'Dashboard en celular');
  agregarImagen(form, '03-inventario-movil.png', 'Inventario en celular');
  form.addGridItem().setTitle('Evalúa la versión para celular')
    .setRows([
      'Se ve bien adaptada a la pantalla del celular',
      'Los botones tienen buen tamaño para tocarlos con el dedo',
      'La información importante se ve sin tener que buscarla',
    ])
    .setColumns(LIKERT).setRequired(true);
  form.addMultipleChoiceItem().setTitle('¿Dónde preferirías usar Operalia en tu trabajo?').setRequired(true)
    .setChoiceValues(['Celular', 'Computadora', 'Ambos por igual']);

  // ── Sección 8: SUS ───────────────────────────────────────────────────────
  form.addPageBreakItem().setTitle('Impresión general (escala SUS)')
    .setHelpText('Con base en todas las pantallas que viste, indica qué tan de acuerdo estás con cada frase. ' +
      'Es la System Usability Scale, un cuestionario estándar de usabilidad.');
  form.addGridItem().setTitle('Escala de usabilidad del sistema')
    .setRows(SUS).setColumns(['1 · Muy en desacuerdo', '2', '3', '4', '5 · Muy de acuerdo']).setRequired(true);

  // ── Sección 9: diseño visual y comentarios ───────────────────────────────
  form.addPageBreakItem().setTitle('Diseño visual y comentarios finales');
  form.addCheckboxItem().setTitle('¿Qué elementos del diseño te gustaron más? (elige los que quieras)')
    .setChoiceValues([
      'Paleta de colores (azul oscuro y blanco)',
      'Iconos',
      'Etiquetas de colores para los estados (Normal, Crítico, Pendiente…)',
      'Menú lateral agrupado por módulos',
      'Tarjetas de indicadores del dashboard',
      'Tipografía',
    ]).showOtherOption(true);
  form.addMultipleChoiceItem().setTitle('El menú lateral tiene muchas opciones. ¿Cómo lo percibes?').setRequired(true)
    .setChoiceValues(['Bien organizado, encuentro todo', 'Útil pero algo saturado', 'Demasiadas opciones, me pierdo']);
  form.addScaleItem().setTitle('Del 1 al 10, ¿qué calificación le das al diseño de Operalia?')
    .setBounds(1, 10).setLabels('Muy malo', 'Excelente').setRequired(true);
  form.addParagraphTextItem().setTitle('¿Qué es lo que MÁS te gustó de la interfaz?');
  form.addParagraphTextItem().setTitle('¿Qué es lo que MENOS te gustó o mejorarías?');

  // ── Acceso público ───────────────────────────────────────────────────────
  // En cuentas de escuela (Workspace) el formulario nace restringido al dominio;
  // esto lo abre a cualquier persona con el enlace.
  try { form.setRequireLogin(false); } catch (e) { Logger.log('setRequireLogin: ' + e); }
  // Los formularios nuevos pueden crearse sin publicar; esto los publica.
  try { if (form.setPublished) form.setPublished(true); } catch (e) { Logger.log('setPublished: ' + e); }
  form.setAcceptingResponses(true);

  Logger.log('✅ Encuesta creada');
  Logger.log('Enlace PÚBLICO (este va en la entrega): ' + form.getPublishedUrl());
  Logger.log('Enlace corto: ' + form.shortenFormUrl(form.getPublishedUrl()));
  Logger.log('Enlace para editar: ' + form.getEditUrl());
}
