import type { Scores } from './sse';

export interface PsiData {
  strategy: string;
  lcp_ms: number | null;
  fcp_ms: number | null;
  cls_score: number | null;
  tbt_ms: number | null;
  speed_index_ms: number | null;
  inp_ms: number | null;
  lighthouse_performance: number | null;
  lighthouse_accessibility: number | null;
  lighthouse_best_practices: number | null;
  lighthouse_seo: number | null;
}

export interface Finding {
  rule_id: string;
  category: string;
  severity: 'critical' | 'warning' | 'info';
  detail: string;
}

export interface KeywordCoverage {
  keyword: string;
  in_title: boolean;
  in_h1: boolean;
  in_description: boolean;
  density_permille: number;
  coverage_score: number;
}

export interface AuditResult {
  url: string;
  status: number;
  body_len: number;
  duration_ms: number;
  profile: string;
  gpu_accelerated: boolean;
  title: string | null;
  description: string | null;
  h1: string | null;
  link_count: number;
  internal_links: number;
  external_links: number;
  heading_count: number;
  has_robots: boolean;
  sitemap_url: string | null;
  hreflang_count: number;
  keyword_analysis: {
    total_words: number;
    top_keywords: Array<{ word: string; count: number }>;
    target_keyword: string | null;
    in_title?: boolean;
    in_h1?: boolean;
    in_description?: boolean;
    density_permille?: number;
  };
  keyword_coverages: KeywordCoverage[];
  aeo_data: {
    has_faq_schema: boolean;
    has_howto_schema: boolean;
    has_article_schema: boolean;
    has_author_entity: boolean;
    has_publisher_entity: boolean;
    has_qa_headings: boolean;
    outbound_link_count: number;
  };
  scores: Scores;
  findings: Finding[];
  psi: PsiData | null;
}
