export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.17"
  }
  public: {
    Tables: {
      app_users: {
        Row: {
          created_at: string
          id: string
          name: string
          password_hash: string
          role: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          password_hash: string
          role?: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          password_hash?: string
          role?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      components: {
        Row: {
          component_name: string
          created_at: string
          created_by: string | null
          cupboard_number: string
          id: string
          is_demo: boolean
          manufacturer: string | null
          package: string | null
          part_number: string
          quantity: number
          specification: string | null
          updated_at: string
          vendor: string | null
        }
        Insert: {
          component_name: string
          created_at?: string
          created_by?: string | null
          cupboard_number: string
          id?: string
          is_demo?: boolean
          manufacturer?: string | null
          package?: string | null
          part_number: string
          quantity?: number
          specification?: string | null
          updated_at?: string
          vendor?: string | null
        }
        Update: {
          component_name?: string
          created_at?: string
          created_by?: string | null
          cupboard_number?: string
          id?: string
          is_demo?: boolean
          manufacturer?: string | null
          package?: string | null
          part_number?: string
          quantity?: number
          specification?: string | null
          updated_at?: string
          vendor?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "components_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      hpt_sessions: {
        Row: {
          created_at: string
          expires_at: string
          id: string
          token_hash: string
          user_id: string
        }
        Insert: {
          created_at?: string
          expires_at: string
          id?: string
          token_hash: string
          user_id: string
        }
        Update: {
          created_at?: string
          expires_at?: string
          id?: string
          token_hash?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "hpt_sessions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      hpt_authenticate_user: {
        Args: { _expect_admin?: boolean; _login_id: string; _password: string }
        Returns: {
          login_id: string
          name: string
          role: string
          session_token: string
          uid: string
        }[]
      }
      hpt_count_components: {
        Args: { _query?: string; _session_token: string }
        Returns: number
      }
      hpt_create_component: {
        Args: {
          _component_name: string
          _cupboard_number: string
          _manufacturer?: string
          _package?: string
          _part_number: string
          _quantity: number
          _session_token: string
          _specification?: string
          _vendor?: string
        }
        Returns: {
          component_name: string
          created_at: string
          created_by: string
          created_by_name: string
          cupboard_number: string
          id: string
          is_demo: boolean
          manufacturer: string | null
          package: string | null
          part_number: string
          quantity: number
          specification: string | null
          updated_at: string
          vendor: string | null
        }[]
      }
      hpt_create_user: {
        Args: {
          _name: string
          _password_hash: string
          _session_token: string
          _user_id: string
        }
        Returns: boolean
      }
      hpt_current_session: {
        Args: { _session_token: string }
        Returns: {
          login_id: string
          name: string
          role: string
          uid: string
        }[]
      }
      hpt_dashboard_stats: { Args: { _session_token: string }; Returns: Json }
      hpt_delete_component: {
        Args: { _id: string; _session_token: string }
        Returns: boolean
      }
      hpt_delete_user: {
        Args: { _id: string; _session_token: string }
        Returns: boolean
      }
      hpt_list_users: {
        Args: { _session_token: string }
        Returns: {
          created_at: string
          id: string
          name: string
          role: string
          status: string
          user_id: string
        }[]
      }
      hpt_logout: { Args: { _session_token: string }; Returns: boolean }
      hpt_pbkdf2_sha256: {
        Args: { _iterations: number; _password: string; _salt_hex: string }
        Returns: string
      }
      hpt_require_session: {
        Args: { _require_admin?: boolean; _session_token: string }
        Returns: {
          login_id: string
          name: string
          role: string
          uid: string
        }[]
      }
      hpt_reset_user_password: {
        Args: { _id: string; _password_hash: string; _session_token: string }
        Returns: boolean
      }
      hpt_search_components: {
        Args: { _limit?: number; _query?: string; _session_token: string }
        Returns: {
          component_name: string
          created_at: string
          created_by: string
          created_by_name: string
          cupboard_number: string
          id: string
          is_demo: boolean
          manufacturer: string | null
          package: string | null
          part_number: string
          quantity: number
          specification: string | null
          updated_at: string
          vendor: string | null
        }[]
      }
      hpt_set_user_status: {
        Args: { _id: string; _session_token: string; _status: string }
        Returns: boolean
      }
      hpt_update_component: {
        Args: {
          _component_name: string
          _cupboard_number: string
          _id: string
          _manufacturer?: string
          _package?: string
          _part_number: string
          _quantity: number
          _session_token: string
          _specification?: string
          _vendor?: string
        }
        Returns: boolean
      }
      hpt_verify_password: {
        Args: { _password: string; _stored: string }
        Returns: boolean
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
